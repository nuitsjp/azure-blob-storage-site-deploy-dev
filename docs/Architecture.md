# Architecture

## 本書の位置づけ

- [`README.md`](../repos/product/README.md): オンボーディングと全体像
- [`Design.md`](Design.md): プロダクト/運用設計（要件・制約・インターフェース）
- `Architecture.md`（本書）: 実装構成、スクリプト分割、テスト戦略

## 実装技術

### Composite Action

本actionはComposite Actionとして実装する。Reusable Workflow（`workflow_call`）ではなくComposite Actionを選択する理由は以下のとおり。

- 呼び出し側のジョブ内でステップとして実行されるため、別ジョブ起動のオーバーヘッドがない
- ステップ単位でロジックを分離でき、テスタビリティが高い

### bash

内部ロジックはbashで実装する。

- GitHub Actionsランナー（`ubuntu-latest`）に標準搭載で追加インストールが不要
- `az cli`もランナーにプリインストール済みであり、環境構築手順なしでAzure操作が可能
- Python・Node.js等のランタイムに依存しないため、実行が軽快

---

## ディレクトリ構成

```
azure-blob-storage-site-deploy/
├── action.yml                      # Composite Action定義
├── scripts/
│   ├── lib/
│   │   ├── validate.sh             # 入力バリデーション関数群
│   │   ├── prefix.sh               # プレフィックス生成・URL組み立て
│   │   └── azure.sh                # az cli呼び出しラッパー（副作用層）
│   ├── deploy.sh                   # deployアクションのエントリーポイント
│   └── cleanup.sh                  # cleanupアクションのエントリーポイント
├── tests/
│   ├── unit/
│   │   ├── test_validate.bats      # バリデーションのテスト
│   │   └── test_prefix.bats        # プレフィックス生成のテスト
│   ├── flow/
│   │   ├── test_deploy.bats        # deployフローのテスト（azモック）
│   │   └── test_cleanup.bats       # cleanupフローのテスト（azモック）
│   └── helpers/
│       └── mock_azure.sh           # az cliのモック（単体・フローテスト用）
├── .github/
│   └── workflows/
│       └── test-unit.yml           # 単体テスト・フローテスト（PRごとに実行）
└── README.md                       # オンボーディング
```

### scripts/ の設計原則：ロジックと副作用の分離

テスタビリティを確保するため、内部スクリプトを以下の2層に分離する。

**ロジック層（`lib/validate.sh`, `lib/prefix.sh`）**: 外部コマンドに依存しない純粋な関数群。入力バリデーション、プレフィックス決定、URL組み立て等を担う。bats-coreで高速に単体テスト可能。

**副作用層（`lib/azure.sh`）**: `az storage blob upload-batch` / `delete-batch` 等のaz cli呼び出しを薄い関数としてラップする。テスト時はモック版（`tests/helpers/mock_azure.sh`）に差し替えることで、Azureへの実接続なしにdeploy.sh / cleanup.shのフロー全体をテストできる。

**エントリーポイント（`deploy.sh`, `cleanup.sh`）**: `action.yml`から呼ばれるスクリプト。ロジック層と副作用層の関数を組み合わせて処理を実行する。

### E2Eリポジトリの配置

E2Eテスト用リポジトリ（`azure-blob-storage-site-deploy-e2e`）は本体リポジトリにサブモジュールとして保持しない。ローカル開発時は、開発用メタリポジトリ `azure-blob-storage-site-deploy-dev` 配下（例: `repos/e2e`）で本体リポジトリと並べて管理する。

### lib/ の関数一覧

```
validate.sh
├── validate_storage_account()      # アカウント名の形式チェック
├── validate_action()               # "deploy" or "cleanup" の検証
├── validate_source_dir()           # ディレクトリ存在チェック（deploy時）
├── validate_branch_name()          # ブランチ名の形式チェック
├── validate_pull_request_number()  # PR番号の正の整数チェック
├── validate_prefix_inputs()        # branch_name / pull_request_number の入力検証
└── validate_site_name()            # サイト識別名の形式チェック（小文字英数字+ハイフン、63文字以内）

prefix.sh
├── build_blob_prefix()             # site_name + target_prefix からBlobプレフィックスを生成（<site_name>/<target_prefix>）
├── resolve_target_prefix()         # branch_name + pull_request_number からプレフィックスを解決
├── build_site_url()                # アカウント名+プレフィックスからURL生成（末尾/保証）
├── build_site_url_from_endpoint()  # エンドポイント+プレフィックスからURL生成（末尾/保証）
└── build_blob_pattern()            # delete-batch用のパターン文字列生成
```

**deploy.sh / cleanup.sh**: `INPUT_SITE_NAME`の環境変数を読み取り、`build_blob_prefix()`でsite_nameとtarget_prefixを結合してから既存関数に渡す。azure.shは結合済みのパスを不透明な文字列として扱う。

---

## テスト方針

### テストフレームワーク

bashスクリプトのテストには**bats-core**（Bash Automated Testing System）を使用する。bashのテストフレームワークとしてデファクトであり、GitHub Actions自体のテストにも広く使われている。ランタイムの追加インストール（npm, pip等）は不要で、apt等で導入できる。

### テスト戦略

| テスト層 | 実行場所 | 対象 | Azureリソース | 実行タイミング |
|---|---|---|---|---|
| 単体テスト | 本体リポジトリ | lib/の関数群 | 不要 | PR作成・更新時 |
| フローテスト | 本体リポジトリ | deploy.sh / cleanup.sh（azモック） | 不要 | PR作成・更新時 |
| E2Eテスト | テスト用リポジトリ（外部。開発時はメタリポジトリ配下で管理） | ライフサイクル全体 | 必要 | 手動 / リリース前 / スケジュール |

### 単体テスト

`lib/validate.sh`と`lib/prefix.sh`の各関数を個別にテストする。外部コマンドへの依存がないため、高速に実行できる。

### フローテスト

`deploy.sh`と`cleanup.sh`のフロー全体をテストする。`tests/helpers/mock_azure.sh`でaz cli関数をモックに差し替え、以下を検証する。

- delete-batch → upload-batchの順序で呼ばれること（deploy時）
- 正しい引数（ストレージアカウント名、プレフィックス、ソースディレクトリ等）が渡されること
- バリデーションエラー時に処理が中断されること

### E2Eテスト

テスト用リポジトリ `azure-blob-storage-site-deploy-e2e` は本体リポジトリとは分離して管理する。ローカル開発では `azure-blob-storage-site-deploy-dev`（開発用メタリポジトリ）配下に配置し、本体リポジトリと同一ワークスペースで扱う。

#### テスト用リポジトリを分離する理由

- action本体リポジトリ内でE2Eを行うと、テスト用のPR作成・クローズがaction自体の開発ワークフローと干渉する
- テスト用リポジトリであれば、テスト目的のブランチ操作やPR作成を自由に行える
- 実際の利用者と同じ「外部からactionを参照する」構成でテストできるため、公開後の動作に忠実

#### テスト用リポジトリの構成

```
azure-blob-storage-site-deploy-e2e/
├── docs/                               # テスト用の静的サイトソース
│   ├── index.html
│   └── sub/
│       └── page.html
├── .github/
│   └── workflows/
│       ├── deploy.yml                  # 本actionを使うワークフロー（テスト対象）
│       └── e2e-orchestrator.yml        # E2Eシナリオを実行するワークフロー
└── e2e/
    └── verify.sh                       # デプロイ結果の検証スクリプト
```

#### E2Eシナリオ

`e2e-orchestrator.yml`がGitHub APIを使って一連のイベントを発生させ、各ステップ後に検証する。

| ステップ | 操作 | 検証内容 |
|---|---|---|
| 1 | `main`ブランチにpush | `<site_name>/main/index.html`がHTTPアクセスで取得できる |
| 2 | テストブランチを作成しPRをopen | `<site_name>/pr-<番号>/index.html`がHTTPアクセスで取得できる |
| 3 | テストブランチにファイル変更をpush | `<site_name>/pr-<番号>/`の内容が更新されている。古いファイルが残っていない |
| 4 | PRをclose | `<site_name>/pr-<番号>/`配下が存在しない（404が返る） |
| 5 | 後片付け | テストブランチを削除 |

各ステップの間には、GitHub APIの`GET /repos/{owner}/{repo}/actions/runs`でワークフローの完了をポーリングし、完了を確認してから検証に進む。

#### E2Eのトリガー方式

| 方式 | 用途 |
|---|---|
| 手動（`workflow_dispatch`） | 開発中の任意のタイミングで実行 |
| action本体からの`repository_dispatch` | actionのリリース前に自動実行 |
| スケジュール（`schedule`） | 定期的な回帰テスト |
