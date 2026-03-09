# speckle analysis (MATLAB reanalysis)

このフォルダは、Pythonで取得した `.npy` データを MATLAB の既存 SCOS 解析フローで再解析するためのスクリプト群です。

## 入力ファイル（計測フォルダ）
`SCOSvsTime_WithNoiseSubtraction_Ver2.m` は、計測フォルダ内の以下ファイルを想定します。

### 必須
- `frames.npy` : 3D配列。Python側は `(N,H,W)` 保存。MATLAB側で `(H,W,N)` へ変換して使用。

### 任意（あると時刻情報が改善）
- `timestamps_camera_us.npy`
- `timestamps_host_elapsed_ms.npy`
- `metadata.json`

## 解析フロー
解析フロー自体は従来版を踏襲し、**入力層のみ**を `.npy` ベースへ置換しています。

1. 計測フォルダから `frames.npy` を読み込み
2. 平均画像から ROI 選択
3. Dark 背景の平均・分散を計算
4. 空間ノイズ項（`spVar`）と smoothing 係数を推定
5. 各フレームで `raw/corrected contrast` と `BFI` を計算
6. 従来どおり `LocalStd*_corr.mat`, `BFI_output.mat`, `BFI_Ch*.mat` を保存

## 互換性方針
- 出力 `.mat` の主要フィールド名は従来を維持。
- TIFFの `frameNames` / `datenum` が無い場合、`timestamps_*.npy` 由来の時刻情報を使います。

## ReadRecord 依存の段階的削除計画
1. 第1段: `SCOSvsTime_WithNoiseSubtraction_Ver2.m` からの直接 `ReadRecord` 呼び出しを削除。
2. 第2段: 他スクリプトの `ReadRecord` 利用を調査。
3. 第3段: 不要化できたら `ReadRecord.m` を非推奨化→削除。
