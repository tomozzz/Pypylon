function [allTimeVec, usedCameraTimestamps] = BuildExposureTimeAxis(timeVecFile, nFrames, frameRate)
% BuildExposureTimeAxis Normalize the global recording time axis in seconds.
%
% Camera timestamps are normalized once for the complete recording. Exposure
% series must then select their own entries with allTimeVec(frameIndices).
% Only old recordings with no camera timestamps fall back to nominal FPS.

validateattributes(nFrames, {'numeric'}, {'scalar','integer','nonnegative','finite'}, mfilename, 'nFrames');
nFrames = double(nFrames);

if nargin < 1 || isempty(timeVecFile)
    timeVecFile = nan(nFrames,1);
else
    validateattributes(timeVecFile, {'numeric'}, {'vector','real'}, mfilename, 'timeVecFile');
    timeVecFile = double(timeVecFile(:));
    if numel(timeVecFile) ~= nFrames
        error('BuildExposureTimeAxis:LengthMismatch', ...
            'The timestamp vector contains %d values, but the recording contains %d frames.', ...
            numel(timeVecFile), nFrames);
    end
end

hasTimestamp = isfinite(timeVecFile);
if ~any(hasTimestamp)
    validateattributes(frameRate, {'numeric'}, {'scalar','real','finite','positive'}, mfilename, 'frameRate');
    allTimeVec = (0:(nFrames-1))' ./ double(frameRate);
    usedCameraTimestamps = false;
    return;
end

if ~all(hasTimestamp)
    error('BuildExposureTimeAxis:PartialTimestamps', ...
        ['Camera timestamps are present for only %d of %d frames. Refusing to ' ...
         'combine camera time with an FPS-derived time axis.'], nnz(hasTimestamp), nFrames);
end

if any(diff(timeVecFile) < 0)
    error('BuildExposureTimeAxis:NonMonotonic', ...
        'Camera timestamps must be monotonically nondecreasing.');
end

% LoadNpyRecordingMeta returns MATLAB datenums when capture_start_unix_s is
% available and elapsed camera seconds otherwise. Preserve that established
% API while producing seconds in both cases.
if ~isempty(timeVecFile) && max(timeVecFile) > 1e5
    allTimeVec = (timeVecFile - timeVecFile(1)) .* 24 .* 3600;
else
    allTimeVec = timeVecFile - timeVecFile(1);
end
usedCameraTimestamps = true;
end
