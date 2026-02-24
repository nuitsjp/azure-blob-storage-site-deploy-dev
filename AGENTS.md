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

## よく使うコマンド

```powershell
git submodule update --init --recursive
git submodule status --recursive
git -C repos/product status
git -C repos/e2e status
```
