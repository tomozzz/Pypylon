# SCOSvsTime / RecordSCOSLong の再分析（Python再構成対応）

このメモは `reference/SCOSvsTime_WithNoiseSubtraction_Ver2.m` と `realtimeSCOS_Base/RecordSCOSLong_Tomoya.m` の処理を、
Python版 `realtimeSCOS.py` で対応づけるための実装指針です。

1. **入力・初期化**: 収録条件（Frame数、window、FR、Gain、expT、BL）を読み込む。  
   → `RealtimeSCOSConfig` / `CameraConfig` に集約。
2. **Dark計測**: レーザーOFFで複数フレームを取得し `dark_mean`, `dark_var` を算出。  
   → `capture_n(...dark_frame_count...)`。
3. **ROI準備**: 元Matlabは GUI円選択。  
   → Pythonは `interactive_roi` または config 円ROI（center/radius）か全画面。
4. **SPノイズ準備**: `nForSP` フレームを平均して `spIm`、その局所分散 `spVar` を算出。  
   → `spatial_frame_count` と `local_std(...)**2` で実装。
5. **本撮像ループ**: 各フレームに対し `im = raw - BL - dark_mean`。
6. **局所統計**: `stdfilt` / `imboxfilt` 相当を window で算出。  
   → `local_std` / `box_mean`。
7. **Raw Contrast**: `mean(std^2 / I^2)` をROI内平均。
8. **Corrected Contrast**:  
   `mean((std^2 - G*I - spVar - 1/12 - darkVarWindow)/I^2)` をROI平均。
9. **BFI**: `BFI = 1 / Kcorr^2`。
10. **rBFI正規化**: 最初10秒基準（平均または5%ile）で正規化。
11. **ライブ表示**: Matlabの3段plot（Kcorr^2, I, BFI）を `matplotlib` で更新。
12. **保存形式変更**: Matlab/Tiff保存ではなく、`npy/npz/json` で保存。  
    - `frames_raw.npy`（ピクセル生データ）
    - `frames_corrected.npy`
    - `dark_mean.npy`, `dark_var.npy`, `spatial_var.npy`, `mask.npy`
    - `scos_timeseries.npz`（time, contrast, BFI, rBFI）

補足: Matlab版の `FitMeanIm` による `fittedI = A*mean + B` は、リアルタイム用途では `imboxfilt` 近似も併用されていたため、
Python版では安定性重視で `box_mean`（局所平均）を採用しています。
