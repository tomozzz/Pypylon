# realtimeSCOS

## Version history

### ver10
* Fixed `RecordFromCameraVarAndMean` saving into a directory path by writing to `meanIm.mat` inside the recording folder.

### ver9
* Fixed invalid backup file paths by using a filesystem-safe timestamp (`yyyy-mm-dd_HH-MM-SS`) and ensuring the backup folder exists before saving.

### ver8
* Limited the number of frames read per loop iteration and yielded to the UI after `getdata` to keep Stop Video / Update ROI / Update Clim responsive during capture.

### ver7
* Fixed invalid default trigger source (`Line2`) by switching to `Line1`, which matches the camera-supported `TriggerSource` values.

### ver6
* Added `drawnow limitrate` and non-blocking frame wait logic in the video loop so the GUI close button (×) can be processed even when frames are not immediately available.

### ver5
* Fixed trigger delay callback typos and guarded `isvalid` checks when the camera source is not initialized.
* Fixed SCOS buffer growth logic to extend `UserData` fields correctly.
* Removed stray debug lines and hardened the stop-video wait loop against missing `src/vid` fields.

### ver4
* Fixed GUI exposure/gain callbacks to write the correct camera parameters even when video is not running.
* Improved GUI close handling by forcing the video loop to stop and cleaning up the video/source objects safely.

### ver3
* Tuned frame batch size to 20 for the provided 700x700 Mono12 @ 40 fps environment.

### ver2
* Reused a precomputed stdfilt window to reduce per-frame allocations.
* Cleared stored initial frames after contrast computation to reduce memory use.

### ver1
* Reduced real-time loop overhead by batching frame reads and minimizing per-frame mask indexing.
* Disabled per-frame Tiff writes by default and added automatic cleanup when enabled.
* Added version tag to the saved info metadata.
