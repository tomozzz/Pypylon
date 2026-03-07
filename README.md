# Pypylon

Baslerカメラを `pypylon` で制御し、Speckle撮像データを **数値配列** として保存・解析するためのリポジトリです。  
現在のメインプログラムは、以下の2本です。

- **Speckle Capture**: 撮像と時刻保存に特化した記録用スクリプト
- **Realtime SCOS**: 撮像しながら SCOS 指標（Kcorr² / BFI / rBFI）を計算・可視化する解析スクリプト

---

## 1. Speckle Capture（記録用）

### 対象ファイル
- 実行スクリプト: `speckle_capture/speckle_capture.py`
- 設定ファイル例: `speckle_capture/capture_config.example.yaml`

### できること
- フレームを `frames.npy`（`(N, H, W)`）として保存
- カメラ内部タイムスタンプを保存
  - `timestamps_camera_ticks.npy`（カメラの生tick）
  - `timestamps_camera_us.npy`（換算できる場合はマイクロ秒）
- ホストPC基準の経過時間も保存
  - `timestamps_host_elapsed_ms.npy`（ms）
- `metadata.json` に実行設定・取得情報を保存
- 取得停止条件を設定可能
  - `frame_count`: 取得フレーム数で停止
  - `measurement_duration_s`: 計測時間（秒）で停止
  - 両方を設定した場合は、先に条件を満たした時点で停止
- `TriggerMode` / `TriggerSource` 設定により、`Line1` 入力トリガ撮像にも対応

### セットアップ
```bash
pip install pypylon numpy pyyaml
```

### 実行方法
```bash
python speckle_capture/speckle_capture.py --config speckle_capture/capture_config.example.yaml
```

保存先をCLIで上書きする場合:
```bash
python speckle_capture/speckle_capture.py --config speckle_capture/capture_config.example.yaml --output-dir ./data/run_001
```

### 代表的な設定項目（`capture_config.example.yaml`）
- 出力先・接続
  - `output_dir`, `camera_index`, `timeout_ms`
- 停止条件
  - `frame_count`, `measurement_duration_s`
- カメラ設定
  - `width`, `height`, `offset_x`, `offset_y`
  - `pixel_format`, `gain`, `exposure_time`, `black_level`
  - `trigger_mode`, `trigger_source`, `trigger_delay`, `trigger_activation`
  - `enable_acquisition_frame_rate`, `acquisition_frame_rate`

### 出力ファイル
- `frames.npy`: shape = `(N, H, W)`
- `timestamps_camera_ticks.npy`: shape = `(N,)`
- `timestamps_camera_us.npy`: shape = `(N,)`
- `timestamps_host_elapsed_ms.npy`: shape = `(N,)`
- `metadata.json`

### 注意
- Baslerカメラ機種によって、ノード名や設定可能値が異なる場合があります。
- カメラ側タイムスタンプ機能が使えない場合は、ホスト時刻ベース値で代替保存されます。
- 取得失敗（dropped/failed）フレームは保存しないため、フレーム数とタイムスタンプ数は一致します。

---

## 2. Realtime SCOS（解析・可視化用）

### 対象ファイル
- 実行エントリポイント: `realtimeSCOS.py`
- 実装本体: `Pypylon_realtime/realtime_scos.py`
- 設定ファイル例: `Pypylon_realtime/realtimeSCOS_config.example.yaml`
- Matlab再分析メモ: `Pypylon_realtime/MATLAB_REANALYSIS.md`

### できること
- Dark補正 + Spatial noise補正 + 量子化ノイズ補正を含む `corrSpeckleContrast` の計算
- `BFI = 1 / corrSpeckleContrast` と `rBFI` の算出
- 時系列のリアルタイム表示
  - `Kcorr^2`
  - 平均強度 `I`
  - `BFI`
- 解析に使った中間データ・最終時系列を `.npy` / `.npz` で保存

### 実行方法
```bash
python realtimeSCOS.py --config Pypylon_realtime/realtimeSCOS_config.example.yaml
```

### 代表的な設定項目（`realtimeSCOS_config.example.yaml`）
- 解析全体
  - `output_dir`, `frame_count`, `dark_frame_count`, `spatial_frame_count`
  - `window_size`, `show_every_n_frames`, `frame_rate_hz`, `actual_gain_du_per_e`
- ROI
  - `interactive_roi`
  - `roi_center_xy`, `roi_radius`
- カメラ設定（`camera:`）
  - `camera_index`, `timeout_ms`, `pixel_format`
  - `width`, `height`, `offset_x`, `offset_y`
  - `exposure_time`, `gain`, `black_level`
  - `trigger_mode`, `trigger_source`
  - `acquisition_frame_rate_enable`, `acquisition_frame_rate`

### 主な出力ファイル
- `frames_raw.npy`
- `frames_corrected.npy`
- `dark_mean.npy`
- `dark_var.npy`
- `spatial_var.npy`
- `mask.npy`
- `scos_timeseries.npz`（`time_s`, `mean_i`, `raw_speckle_contrast`, `corr_speckle_contrast`, `bfi`, `rbfi`）
- `metadata.json`

### 注意
- 本プログラムは matplotlib によるリアルタイム描画を行います。
- `frame_rate_hz` は時系列軸生成にも使うため、実測FPSに近い値を設定してください。

---

## どちらを使うべきか
- **まず撮像データを確実に保存したい** → `speckle_capture/speckle_capture.py`
- **撮像しながらSCOS指標を見たい／そのまま解析したい** → `realtimeSCOS.py`

---

## 既存 Matlab 資産
- `realtimeSCOS_Base/` と `reference/` には、既存の Matlab ベース実装・参照コードが含まれます。
- Python実装の比較・確認時に参照してください。
