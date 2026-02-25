# azure-blob-storage-site-deploy-dev

`azure-blob-storage-site-deploy` 本体とE2Eリポジトリを同一ワークスペースで扱うための開発用メタリポジトリです。

## リポジトリ構成

```text
azure-blob-storage-site-deploy-dev/
├── repos/
│   ├── product/   # azure-blob-storage-site-deploy（Composite Action 本体）
│   └── e2e/       # azure-blob-storage-site-deploy-e2e（E2E テスト用リポジトリ）
├── scripts/       # devリポジトリのスクリプト群
│   ├── test.sh        # テスト実行ファサード
│   ├── release.sh     # リリーススクリプト
│   └── e2e/           # E2E オーケストレーター（ローカル実行スクリプト）
└── docs/          # 設計ドキュメント
```

| リポジトリ | 役割 | URL |
|---|---|---|
| **dev**（本リポジトリ） | 開発ハブ・テスト実行 | [azure-blob-storage-site-deploy-dev](https://github.com/nuitsjp/azure-blob-storage-site-deploy-dev) |
| **product** | Composite Action本体 | [azure-blob-storage-site-deploy](https://github.com/nuitsjp/azure-blob-storage-site-deploy) |
| **e2e** | E2Eテスト用リポジトリ | [azure-blob-storage-site-deploy-e2e](https://github.com/nuitsjp/azure-blob-storage-site-deploy-e2e) |

Git依存方向: `e2e → product`（E2Eがproductアクションを `uses:` で参照）

## セットアップ

### 1. リポジトリのクローンとサブモジュール初期化

```bash
git clone https://github.com/nuitsjp/azure-blob-storage-site-deploy-dev.git
cd azure-blob-storage-site-deploy-dev
git submodule update --init --recursive
```

### 2. justのインストール

本リポジトリはタスクランナー [just](https://github.com/casey/just) を使用する。

```bash
# macOS
brew install just

# Linux / WSL（プリビルドバイナリ）
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
```

### 3. 開発環境セットアップ

```bash
just setup
```

`just setup` は以下をまとめて実行する:

- **gh** / **jq** の導入（Homebrew / apt-get 対応）
- **bats-core** の導入（`repos/product/.tools/` にローカルインストール）
- **doctor** による前提条件の診断

`gh` のログインが未実施の場合は `gh auth login` を案内して終了する。

## 使い方

`just` で利用可能なタスク一覧を確認できる。主要なコマンド:

```bash
just test             # 単体 + フロー + E2E（デフォルト）
just test-unit        # 単体テストのみ
just test-flow        # フローテストのみ
just test-e2e         # E2E テスト（実Azure / gh / jq 必要）
just release v1.2.3   # 指定バージョンでリリース
just release-auto     # パッチバージョン自動インクリメント
just doctor           # 前提条件の診断
just status           # 各リポジトリの状態確認
just log              # 各リポジトリのログ確認
```

## 開発ワークフロー

### 基本的な流れ

1. **作業ブランチ作成** — `repos/product` または `repos/e2e` 内でブランチを作成（`main` を直接編集しない）
2. **実装** — `repos/product/scripts/` 配下のスクリプトを編集
3. **単体テスト・フローテスト** — `just test-unit` / `just test-flow` で高速にフィードバックを得る
4. **PR作成** — productリポジトリにPRを作成（CIが自動でテスト実行）
5. **E2Eテスト** — リリース前に `just test-e2e`（または `just test`）で実Azure環境を検証
6. **マージ・リリース** — PRマージ後、`just release v1.2.3` でタグ作成・GitHub Releaseを発行

### リリース

リリース前に必ず全テストを実行して問題がないことを確認する。

```bash
just test             # 単体 + フロー + E2E を一括実行
just release v1.2.3   # 指定バージョンでリリース
just release-auto     # パッチバージョン自動インクリメント
```

セマンティックバージョニングタグ（`v1.2.3`）に加え、メジャーバージョンタグ（`v1`）も自動更新される。

## 設計ドキュメント

| ドキュメント | 内容 |
|---|---|
| [`docs/design.md`](docs/design.md) | プロダクト設計（背景・要件・制約・インターフェース） |
| [`docs/architecture.md`](docs/architecture.md) | 実装構成とスクリプト分割 |
| [`docs/deploy.md`](docs/deploy.md) | deploy.shの詳細設計 |
| [`docs/cleanup.md`](docs/cleanup.md) | cleanup.shの詳細設計 |
| [`docs/e2e.md`](docs/e2e.md) | E2Eテストの詳細設計 |
