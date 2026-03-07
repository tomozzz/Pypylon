# Pypylon

Baslerカメラを `pypylon` で制御し、
- Speckle撮像データを保存する
- Realtime SCOS（`corrSpeckleContrast`, `BFI`, `rBFI`）を計算・表示する
ためのリポジトリです。

## セットアップ
```bash
pip install pypylon numpy pyyaml matplotlib
```

---

## 1) Speckle撮像（`speckle_capture/speckle_capture.py`）

### 実行
```bash
python speckle_capture/speckle_capture.py \
  --config speckle_capture/capture_config.example.yaml
```

### プログラムの流れ
1. 設定ファイルを読み込む。  
2. カメラに接続し、解像度・露光・ゲイン・トリガなどを適用。  
3. フレーム取得を開始。  
4. 停止条件（`frame_count` または `measurement_duration_s`）まで取得。  
5. `frames.npy`、タイムスタンプ配列、`metadata.json` を保存。  

### パラメータ（`capture_config.example.yaml`）

#### まず設定すべき最小項目
- `output_dir`: 保存先フォルダ
- `measurement_duration_s` **または** `frame_count`: 停止条件
- `exposure_time`: 露光時間（明るさを決める最重要項目）
- `gain`: ゲイン（露光で足りないときに調整）

#### 各項目の意味
- `output_dir`: 出力先ディレクトリ。
- `camera_index`: 使用カメラ番号（複数接続時）。
- `timeout_ms`: 1フレーム待機のタイムアウト。
- `frame_count`: 取得フレーム数で停止（`null`で無効）。
- `measurement_duration_s`: 取得時間で停止（`null`で無効）。
- `width`, `height`: 撮像サイズ。
- `offset_x`, `offset_y`: ROI左上オフセット。
- `pixel_format`: 画素フォーマット（例: `Mono12`）。
- `gain`: アナログ/デジタル増幅量。
- `exposure_time`: 露光時間（通常 µs）。
- `black_level`: 黒レベルオフセット。
- `trigger_mode`: トリガ使用有無（`On`/`Off`）。
- `trigger_source`: トリガ入力源（例: `Line1`, `Software`）。
- `trigger_delay`: トリガから露光開始までの遅延。
- `trigger_activation`: エッジ条件（`RisingEdge` など）。
- `enable_acquisition_frame_rate`: フレームレート制御を有効化するか。
- `acquisition_frame_rate`: 目標フレームレート（fps）。

### 出力
- `frames.npy`（`(N,H,W)`）
- `timestamps_camera_ticks.npy`
- `timestamps_camera_us.npy`
- `timestamps_host_elapsed_ms.npy`
- `metadata.json`

---

## 2) Realtime SCOS（`realtimeSCOS.py`）

### 実行
```bash
python realtimeSCOS.py \
  --config Pypylon_realtime/realtimeSCOS_config.example.yaml
```

### プログラムの流れ
1. 設定ファイルを読み込む。  
2. カメラ接続・設定適用。  
3. `dark_frame_count` 枚を取得して `dark_mean`, `dark_var` を作成。  
4. `spatial_frame_count` 枚を取得して空間ノイズ項（`spatial_var`）を作成。  
5. ROIを決定（`interactive_roi` か `roi_center_xy` + `roi_radius`）。  
6. 本計測フレームを取得し、各フレームで `corrSpeckleContrast` / `BFI` を計算。  
7. 時系列をリアルタイム描画し、最後に `.npy/.npz` と `metadata.json` を保存。  

### パラメータ（`realtimeSCOS_config.example.yaml`）

#### まず設定すべき最小項目
- `output_dir`: 保存先
- `frame_count`: 本計測フレーム数
- `dark_frame_count`, `spatial_frame_count`: 補正用フレーム数
- `frame_rate_hz`: 時系列軸の基準FPS
- `actual_gain_du_per_e`: 量子化/ショットノイズ補正に使うゲイン係数
- `camera.exposure_time`, `camera.gain`: 信号レベル調整

#### 各項目の意味
- `output_dir`: 出力先ディレクトリ。
- `frame_count`: 本計測フレーム数。
- `dark_frame_count`: ダーク統計作成用フレーム数。
- `spatial_frame_count`: 空間ノイズ統計作成用フレーム数。
- `window_size`: 局所統計（平均/分散）の計算窓サイズ。
- `show_every_n_frames`: 何フレームごとにプロット更新するか。
- `frame_rate_hz`: 時間軸生成に使うFPS。
- `actual_gain_du_per_e`: DU/e⁻ 換算係数。
- `interactive_roi`: GUIクリックでROIを決めるか。
- `roi_center_xy`, `roi_radius`: 円形ROIの中心・半径。
- `camera.*`: カメラ設定（`camera_index`, `timeout_ms`, `pixel_format`, `width/height`, `exposure_time`, `gain`, `black_level`, トリガ関連, フレームレート関連）。

### 出力
- `frames_raw.npy`, `frames_corrected.npy`
- `dark_mean.npy`, `dark_var.npy`, `spatial_var.npy`
- `mask.npy`
- `scos_timeseries.npz`（`time_s`, `mean_i`, `raw_speckle_contrast`, `corr_speckle_contrast`, `bfi`, `rbfi`）
- `metadata.json`

---

## 設定の目安（最初の1回）
- まずは **露光時間 (`exposure_time`)** を調整して飽和しない範囲で信号を確保。
- 次に **ゲイン (`gain`)** を最小限だけ上げる。
- `frame_count` / `measurement_duration_s` は短め（例: 5〜10秒 or 数百フレーム）で確認。
- Realtime SCOSでは、`dark_frame_count` と `spatial_frame_count` を十分に確保（まずは設定例の値から開始）。
