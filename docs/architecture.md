# architecture

## 本書の位置づけ

- [`design.md`](design.md): プロダクト設計（背景・要件・制約・インターフェース）
- `architecture.md`（本書）: 実装構成とスクリプト分割
- [`deploy.md`](deploy.md) / [`cleanup.md`](cleanup.md): 各スクリプトの詳細設計
- [`e2e.md`](e2e.md): E2Eテストの詳細設計

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
└── README.md
```

### scripts/ の設計原則：ロジックと副作用の分離

テスタビリティを確保するため、内部スクリプトを以下の2層に分離する。

**ロジック層（`lib/validate.sh`, `lib/prefix.sh`）**: 外部コマンドに依存しない純粋な関数群。入力バリデーション、プレフィックス決定、URL組み立て等を担う。bats-coreで高速に単体テスト可能。

**副作用層（`lib/azure.sh`）**: `az storage blob upload-batch` / `delete-batch` 等のaz cli呼び出しを薄い関数としてラップする。テスト時はモック版（`tests/helpers/mock_azure.sh`）に差し替えることで、Azureへの実接続なしにdeploy.sh / cleanup.shのフロー全体をテストできる。

**エントリーポイント（`deploy.sh`, `cleanup.sh`）**: `action.yml`から呼ばれるスクリプト。ロジック層と副作用層の関数を組み合わせて処理を実行する。

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
├── build_site_url()                # エンドポイント+プレフィックスからURL生成（末尾/保証）
└── build_blob_pattern()            # delete-batch用のパターン文字列生成
```

**deploy.sh / cleanup.sh**: `INPUT_SITE_NAME`の環境変数を読み取り、`build_blob_prefix()`でsite_nameとtarget_prefixを結合してから既存関数に渡す。azure.shは結合済みのパスを不透明な文字列として扱う。

---

## テスト方針

bashスクリプトのテストには**bats-core**（Bash Automated Testing System）を使用する。

| テスト層 | 対象 | Azureリソース | 実行タイミング |
|---|---|---|---|
| 単体テスト | lib/の関数群 | 不要 | PR作成・更新時（CI自動） |
| フローテスト | deploy.sh / cleanup.sh（azモック） | 不要 | PR作成・更新時（CI自動） |
| E2Eテスト | ライフサイクル全体 | 必要 | 手動 / リリース前 |

**単体テスト**: `lib/validate.sh`と`lib/prefix.sh`の各関数を個別にテストする。外部コマンドへの依存がないため、高速に実行できる。

**フローテスト**: `deploy.sh`と`cleanup.sh`のフロー全体をテストする。`tests/helpers/mock_azure.sh`でaz cli関数をモックに差し替え、実行順序・引数・エラー時の中断を検証する。

**E2Eテスト**: テスト用リポジトリを使い、実Azure環境でライフサイクル全体を検証する。詳細は[`e2e.md`](e2e.md)を参照。

テストの実行方法は[README.md](../README.md)を参照。
