# Repository Guidelines

## Primary Directive

- Think in English, interact with the user in Japanese.
- すべての説明・ドキュメント・コメントは日本語で記述する。
- 識別子（クラス名、関数名、変数名、ファイル名の一部）は英語を使う。

## 役割

このリポジトリは開発用メタリポジトリです。実装対象は主に以下の子リポジトリです。

- `repos/product`: `azure-blob-storage-site-deploy`
- `repos/e2e`: `azure-blob-storage-site-deploy-e2e`

## 作業ルール

- `repos/product` / `repos/e2e` では `main` ブランチを直接編集しない。
- 変更前に対象リポジトリごとに作業ブランチを作成する。
- どちらのリポジトリを変更したかを明確にして報告する。
- サブモジュール更新後は `git submodule status` で状態を確認する。

## 設計ドキュメント

設計ドキュメントは `docs/` に集約:

- `docs/design.md` — プロダクト設計（背景・要件・制約・インターフェース）
- `docs/architecture.md` — 実装構成とスクリプト分割
- `docs/deploy.md` — deploy.shの詳細設計
- `docs/cleanup.md` — cleanup.shの詳細設計
- `docs/e2e.md` — E2Eテストの詳細設計

## よく使うコマンド

```bash
git submodule update --init --recursive
git submodule status --recursive
git -C repos/product status
git -C repos/e2e status

# テスト実行
./test.sh          # 単体テスト + フローテスト
./test.sh unit     # 単体テストのみ
./test.sh flow     # フローテストのみ

# E2Eテスト（Azure環境必要）
./e2e/orchestrator.sh

# リリース
./release.sh v1.2.3   # 指定バージョンでリリース
./release.sh          # パッチバージョンを自動インクリメント
```

## テストガイドライン

- 実装コードを追加する際は、`tests/`のBats構造に従ってテストも追加する。
- テスト優先順位: 純粋関数の単体テスト → モック付きフローテスト → E2Eテスト。
- PR作成前に、変更範囲に応じたテスト/検証コマンドを必ず実行する。

## コミット・PRガイドライン

- Conventional Commitスタイル: `feat: ...`, `docs: ...`, `fix: ...`。日本語コミットメッセージも可。
- PR本文には目的、変更ファイル/変更範囲、実施した検証（コマンドと結果、例: `34件 pass`）、影響範囲を含める。
- 子IssueはPR作成・レビュー中の段階ではCloseしない。原則としてPRマージ後にCloseし、親Issueのチェックリストも同時に更新する。
- クロスリポジトリの影響がある場合は明示的に記載する。
