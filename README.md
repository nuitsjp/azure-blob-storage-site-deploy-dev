# azure-blob-storage-site-deploy-dev

`azure-blob-storage-site-deploy` 本体と E2E リポジトリを同一ワークスペースで扱うための開発用メタリポジトリです。

## 目的

- Git の依存関係は `e2e -> product` を維持する
- ローカル作業では `product` と `e2e` を同時に編集・確認できるようにする
- AI コーディングエージェントが横断的に作業しやすい作業ハブを提供する

## 構成

```text
repos/
├── product/  # azure-blob-storage-site-deploy
└── e2e/      # azure-blob-storage-site-deploy-e2e
```

## セットアップ

```powershell
git submodule update --init --recursive
```

## 運用ルール（要点）

- `repos/product` と `repos/e2e` は独立したリポジトリとして扱う
- 各リポジトリで `main` を直接編集しない
- E2E の参照先は `repos/e2e` 側のワークフロー（`uses:`）で管理する
