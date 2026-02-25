# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Policy

- Think in English, interact with the user in Japanese.
- すべての説明・ドキュメント・コメントは日本語で記述する。
- 識別子（クラス名、関数名、変数名、ファイル名の一部）は英語を使う。
- コミットメッセージは日本語でも可。Conventional Commitsスタイル (`feat:`, `docs:`, `fix:` 等) を使う。

## Repository Overview

開発用メタリポジトリ。2つの独立したリポジトリをサブモジュールとして束ね、AIコーディングエージェントが横断的に作業できるハブを提供する。

- **`repos/product`** — `azure-blob-storage-site-deploy`: Azure Blob Storageへ静的サイトをデプロイするGitHub Actions Composite Action
- **`repos/e2e`** — `azure-blob-storage-site-deploy-e2e`: 上記アクションのE2Eテスト

Git依存方向: `e2e → product`（E2Eがproductアクションを `uses:` で参照）

## Branching Rules

- `repos/product` / `repos/e2e` では **`main` ブランチを直接編集しない**。必ず作業ブランチを作成する。
- どちらのリポジトリを変更したかを明確にして報告する。

## Common Commands

タスクランナー `just` を使用する。`just` で全タスク一覧を確認できる。

```bash
# セットアップ
just setup              # 開発環境セットアップ（gh/jq, bats-core, doctor）
just doctor             # 前提条件の診断

# テスト
just test               # 単体 + フロー + E2E（デフォルト）
just test-unit          # 単体テストのみ
just test-flow          # フローテストのみ
just test-e2e           # E2Eテスト（実Azure / gh / jq 必要）

# リリース
just release v1.2.3     # 指定バージョンでリリース
just release-auto       # パッチバージョン自動インクリメント

# サブモジュール・状態確認
just status             # 各リポジトリの状態確認
just log                # 各リポジトリのログ確認

# 作業ブランチ作成
just branch-product NAME  # repos/product でブランチ作成
just branch-e2e NAME      # repos/e2e でブランチ作成
```

## Design Documents

設計ドキュメントはメタリポジトリの `docs/` に集約:

- [`docs/design.md`](docs/design.md) — プロダクト設計（背景・要件・制約・インターフェース）
- [`docs/architecture.md`](docs/architecture.md) — 実装構成とスクリプト分割
- [`docs/deploy.md`](docs/deploy.md) — deploy.shの詳細設計
- [`docs/cleanup.md`](docs/cleanup.md) — cleanup.shの詳細設計
- [`docs/e2e.md`](docs/e2e.md) — E2Eテストの詳細設計

## Architecture

### Product (`repos/product`) — Composite Action

実装言語はbash。ビルドステップなしのシェルベースComposite Action。

ロジックと副作用の分離を基本設計原則とする:

1. **Logic Layer** (`scripts/lib/validate.sh`, `scripts/lib/prefix.sh`) — 純粋関数、外部依存なし
2. **Effect Layer** (`scripts/lib/azure.sh`) — `az` CLIの薄いラッパー、モックでテスト可能
3. **Entrypoints** (`scripts/deploy.sh`, `scripts/cleanup.sh`) — Logic + Effectを組み合わせるオーケストレーター、`action.yml` から呼ばれる

テスト時は `tests/helpers/mock_azure.sh` で `az` 関数をモックに差し替え、呼び出し引数をログファイルに記録してアサーションする。

### E2E (`repos/e2e`) — E2Eテスト用リポジトリ

Composite Actionの「利用者」として最低限必要なリソースのみ配置:

- `.github/workflows/deploy.yml` — push/PRトリガーのデプロイワークフロー
- `docs/` — テスト用静的サイトコンテンツ

E2Eテストの実行スクリプトはdevリポジトリの `scripts/e2e/` に配置:

- `scripts/e2e/orchestrator.sh` — ライフサイクル全体のE2Eシナリオ実行
- `scripts/e2e/lib.sh` — 共有ヘルパー関数
- `scripts/e2e/verify.sh` — HTTP検証スクリプト（リトライ・コンテンツ検証）

### Test Strategy

| テスト層 | 実行場所 | Azureリソース | 実行タイミング |
|---|---|---|---|
| 単体テスト | `repos/product/tests/unit/` | 不要 | PR作成・更新時 |
| フローテスト | `repos/product/tests/flow/`（azモック） | 不要 | PR作成・更新時 |
| E2Eテスト | `scripts/e2e/`（devリポジトリからローカル実行） | 必要 | 手動 / リリース前 |

CIは `repos/product/.github/workflows/test-unit.yml` でPRごとに単体テスト・フローテストを実行。

### Key Design Decisions

- **PR番号ベースのプレフィックス** (`pr-<number>`): ブランチ名ではなくPR番号を使用。日本語文字のエンコード問題、スラッシュのディレクトリ区切り解釈、永続ブランチとの名前衝突を回避。
- **ファイル同期戦略**: プレフィックスディレクトリを全削除してからアップロード（古いファイルの残留を防止）
- **OIDC認証**: AzureへはFederated Credentialsで接続（シークレット不要）
- **Composite Action over Reusable Workflow**: 呼び出し側ジョブ内のステップとして実行（別ジョブ起動のオーバーヘッドなし）
- **URL末尾スラッシュ**: Azure Blob Storageは `/pr-42` → `/pr-42/` の自動リダイレクトをしないため、URLには必ず末尾 `/` を付与

## Coding Conventions

- ファイル名: 小文字、テストは `test_*.bats`
- Bashスクリプト: 小さな関数に分割、副作用はラッパーに隔離（`scripts/lib/azure.sh`）
- テスト優先順位: ユニットテスト（純粋関数）→ フローテスト（モック）→ E2E（Azure実環境、外部リポジトリ）
- PRステージングプレフィックス: `pr-<number>`
