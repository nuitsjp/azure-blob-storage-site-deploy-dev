# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Policy

- Think in English, interact with the user in Japanese.
- すべての説明・ドキュメント・コメントは日本語で記述する。
- 識別子（クラス名、関数名、変数名、ファイル名の一部）は英語を使う。
- コミットメッセージは日本語でも可。Conventional Commits スタイル (`feat:`, `docs:`, `fix:` 等) を使う。

## Repository Overview

開発用メタリポジトリ。2つの独立したリポジトリをサブモジュールとして束ね、AI コーディングエージェントが横断的に作業できるハブを提供する。

- **`repos/product`** — `azure-blob-storage-site-deploy`: Azure Blob Storage へ静的サイトをデプロイする GitHub Actions Composite Action
- **`repos/e2e`** — `azure-blob-storage-site-deploy-e2e`: 上記アクションの E2E テスト

Git 依存方向: `e2e → product`（E2E が product アクションを `uses:` で参照）

## Branching Rules

- `repos/product` / `repos/e2e` では **`main` ブランチを直接編集しない**。必ず作業ブランチを作成する。
- どちらのリポジトリを変更したかを明確にして報告する。

## Common Commands

```bash
# サブモジュール初期化
git submodule update --init --recursive

# サブモジュール状態確認
git submodule status --recursive
git -C repos/product status
git -C repos/e2e status

# サブモジュール内のログ確認
git -C repos/product log --oneline -n 10
git -C repos/e2e log --oneline -n 10
```

テスト実行:
```bash
# 単体テスト + フローテスト（デフォルト）
./test.sh

# 単体テストのみ / フローテストのみ
./test.sh unit
./test.sh flow
```

E2Eテスト:
```bash
# ライフサイクル全体の E2E テスト（Azure 環境必要）
./e2e/orchestrator.sh
```

リリース:
```bash
# 指定バージョンでリリース
./release.sh v1.2.3

# パッチバージョンを自動インクリメント
./release.sh
```

## Design Documents

設計ドキュメントはメタリポジトリの `docs/` に集約:

- [`docs/design.md`](docs/design.md) — プロダクト設計（背景・要件・制約・インターフェース）
- [`docs/architecture.md`](docs/architecture.md) — 実装構成とスクリプト分割
- [`docs/deploy.md`](docs/deploy.md) — deploy.sh の詳細設計
- [`docs/cleanup.md`](docs/cleanup.md) — cleanup.sh の詳細設計
- [`docs/e2e.md`](docs/e2e.md) — E2Eテストの詳細設計

## Architecture

### Product (`repos/product`) — Composite Action

実装言語は bash。ビルドステップなしのシェルベース Composite Action。

ロジックと副作用の分離を基本設計原則とする:

1. **Logic Layer** (`scripts/lib/validate.sh`, `scripts/lib/prefix.sh`) — 純粋関数、外部依存なし
2. **Effect Layer** (`scripts/lib/azure.sh`) — `az` CLI の薄いラッパー、モックでテスト可能
3. **Entrypoints** (`scripts/deploy.sh`, `scripts/cleanup.sh`) — Logic + Effect を組み合わせるオーケストレーター、`action.yml` から呼ばれる

テスト時は `tests/helpers/mock_azure.sh` で `az` 関数をモックに差し替え、呼び出し引数をログファイルに記録してアサーションする。

### E2E (`repos/e2e`) — E2E テスト用リポジトリ

Composite Actionの「利用者」として最低限必要なリソースのみ配置:

- `.github/workflows/deploy.yml` — push/PR トリガーのデプロイワークフロー
- `docs/` — テスト用静的サイトコンテンツ

E2Eテストの実行スクリプトはdevリポジトリの `e2e/` に配置:

- `e2e/orchestrator.sh` — ライフサイクル全体のE2Eシナリオ実行
- `e2e/lib.sh` — 共有ヘルパー関数
- `e2e/verify.sh` — HTTP 検証スクリプト（リトライ・コンテンツ検証）

### Test Strategy

| テスト層 | 実行場所 | Azure リソース | 実行タイミング |
|---|---|---|---|
| 単体テスト | `repos/product/tests/unit/` | 不要 | PR 作成・更新時 |
| フローテスト | `repos/product/tests/flow/`（az モック） | 不要 | PR 作成・更新時 |
| E2E テスト | `e2e/`（devリポジトリからローカル実行） | 必要 | 手動 / リリース前 |

CI は `repos/product/.github/workflows/test-unit.yml` で PR ごとに単体テスト・フローテストを実行。

### Key Design Decisions

- **PR番号ベースのプレフィックス** (`pr-<number>`): ブランチ名ではなくPR番号を使用。日本語文字のエンコード問題、スラッシュのディレクトリ区切り解釈、永続ブランチとの名前衝突を回避。
- **ファイル同期戦略**: プレフィックスディレクトリを全削除してからアップロード（古いファイルの残留を防止）
- **OIDC 認証**: Azure へは Federated Credentials で接続（シークレット不要）
- **Composite Action over Reusable Workflow**: 呼び出し側ジョブ内のステップとして実行（別ジョブ起動のオーバーヘッドなし）
- **URL 末尾スラッシュ**: Azure Blob Storage は `/pr-42` → `/pr-42/` の自動リダイレクトをしないため、URL には必ず末尾 `/` を付与

## Coding Conventions

- ファイル名: 小文字、テストは `test_*.bats`
- Bash スクリプト: 小さな関数に分割、副作用はラッパーに隔離（`scripts/lib/azure.sh`）
- テスト優先順位: ユニットテスト（純粋関数）→ フローテスト（モック）→ E2E（Azure 実環境、外部リポジトリ）
- PR ステージングプレフィックス: `pr-<number>`
