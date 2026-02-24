# azure-blob-storage-site-deploy-dev

`azure-blob-storage-site-deploy` 本体と E2E リポジトリを同一ワークスペースで扱うための開発用メタリポジトリです。

## リポジトリ構成

```text
azure-blob-storage-site-deploy-dev/
├── repos/
│   ├── product/   # azure-blob-storage-site-deploy（Composite Action 本体）
│   └── e2e/       # azure-blob-storage-site-deploy-e2e（E2E テスト用リポジトリ）
├── e2e/           # E2E オーケストレーター（ローカル実行スクリプト）
├── docs/          # 設計ドキュメント
├── test.sh        # テスト実行ファサード
└── release.sh     # リリーススクリプト
```

| リポジトリ | 役割 | URL |
|---|---|---|
| **dev**（本リポジトリ） | 開発ハブ・テスト実行 | [azure-blob-storage-site-deploy-dev](https://github.com/nuitsjp/azure-blob-storage-site-deploy-dev) |
| **product** | Composite Action 本体 | [azure-blob-storage-site-deploy](https://github.com/nuitsjp/azure-blob-storage-site-deploy) |
| **e2e** | E2Eテスト用リポジトリ | [azure-blob-storage-site-deploy-e2e](https://github.com/nuitsjp/azure-blob-storage-site-deploy-e2e) |

Git 依存方向: `e2e → product`（E2E が product アクションを `uses:` で参照）

## セットアップ

### 1. リポジトリのクローンとサブモジュール初期化

```bash
git clone https://github.com/nuitsjp/azure-blob-storage-site-deploy-dev.git
cd azure-blob-storage-site-deploy-dev
git submodule update --init --recursive
```

### 2. bats-core のインストール

単体テスト・フローテストに必要なテストフレームワーク。`test.sh` 実行時に未導入であれば自動インストールされるため、手動での実行は任意。

```bash
bash repos/product/scripts/install-bats.sh
```

`repos/product/.tools/` 配下にローカルインストールされる（グローバル環境を汚染しない）。

### 3. GitHub CLI（E2E テスト・リリース時）

E2E テストおよびリリースを実行する場合は、以下が追加で必要。

- **GitHub CLI** — `gh auth status` でログイン済みであること（E2E テスト・リリースの両方で使用）
- **jq** — JSON パース用（E2E テストで使用）

## テスト

3 層のテスト戦略をとる。単体テスト・フローテストは Azure 不要で高速に実行でき、E2E テストは実際の Azure 環境でライフサイクル全体を検証する。

```text
単体テスト ──→ フローテスト ──→ E2E テスト ──→ リリース
 (秒単位)       (秒単位)        (分単位)
 Azure不要      Azure不要       Azure必要
 PR時にCI自動   PR時にCI自動    手動/リリース前
```

### 単体テスト・フローテスト

`test.sh` で product リポジトリのテストをまとめて実行できる。bats-core が未導入の場合は自動でインストールされる。

```bash
./test.sh          # 単体テスト + フローテスト（デフォルト）
./test.sh unit     # 単体テストのみ
./test.sh flow     # フローテストのみ
./test.sh all      # 単体テスト + フローテスト
```

| サブコマンド | 対象 | テストディレクトリ |
|---|---|---|
| `unit` | バリデーション・プレフィックス生成等の純粋関数 | `repos/product/tests/unit/` |
| `flow` | deploy.sh / cleanup.sh のフロー全体（az モック使用） | `repos/product/tests/flow/` |
| `all`（デフォルト） | 上記両方を順次実行 | — |

### E2E テスト

product リポジトリの実装を修正した後、リリース前に実行する。ローカルからシェルスクリプトで e2e リポジトリを操作し、main push → PR 作成 → PR 更新 → PR クローズのライフサイクル全体を検証する。

```bash
./e2e/orchestrator.sh
```

詳細は [`docs/e2e.md`](docs/e2e.md) を参照。

## 開発ワークフロー

### 基本的な流れ

1. **作業ブランチ作成** — `repos/product` または `repos/e2e` 内でブランチを作成（`main` を直接編集しない）
2. **実装** — `repos/product/scripts/` 配下のスクリプトを編集
3. **単体テスト・フローテスト** — `./test.sh` で高速にフィードバックを得る
4. **PR 作成** — product リポジトリに PR を作成（CI が自動でテスト実行）
5. **E2E テスト** — リリース前に `./e2e/orchestrator.sh` で実 Azure 環境を検証
6. **マージ・リリース** — PR マージ後、`./release.sh` でタグ作成・GitHub Release を発行

### リリース

`release.sh` で product リポジトリのタグ作成と GitHub Release を行う。

```bash
./release.sh v1.2.3   # 指定バージョンでリリース
./release.sh          # パッチバージョンを自動インクリメント
```

セマンティックバージョニングタグ（`v1.2.3`）に加え、メジャーバージョンタグ（`v1`）も自動更新される。

### サブモジュール操作

```bash
# サブモジュール状態確認
git submodule status --recursive

# 各リポジトリの状態確認
git -C repos/product status
git -C repos/e2e status

# 各リポジトリのログ確認
git -C repos/product log --oneline -n 10
git -C repos/e2e log --oneline -n 10
```

## 設計ドキュメント

| ドキュメント | 内容 |
|---|---|
| [`docs/design.md`](docs/design.md) | プロダクト設計（背景・要件・制約・インターフェース） |
| [`docs/architecture.md`](docs/architecture.md) | 実装構成とスクリプト分割 |
| [`docs/deploy.md`](docs/deploy.md) | deploy.sh の詳細設計 |
| [`docs/cleanup.md`](docs/cleanup.md) | cleanup.sh の詳細設計 |
| [`docs/e2e.md`](docs/e2e.md) | E2Eテストの詳細設計 |

## 運用ルール

- `repos/product` と `repos/e2e` は独立したリポジトリとして扱う
- 各リポジトリで `main` を直接編集しない（必ず作業ブランチを作成）
- E2E の参照先は `repos/e2e` 側のワークフロー（`uses:`）で管理する
