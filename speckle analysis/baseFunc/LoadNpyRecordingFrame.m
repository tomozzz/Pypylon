function [im, t, frameName, exposureTimeUs, sequencerSetId] = LoadNpyRecordingFrame(recPath, frameIndex, sourceFiles)
% LoadNpyRecordingFrame Load one frame (1-based) from npy/chunked recording.
% Optional outputs exposureTimeUs and sequencerSetId are NaN for legacy data.
if nargin < 3 || isempty(sourceFiles)
    error('LoadNpyRecordingFrame:MissingSource','sourceFiles metadata is required. Call LoadNpyRecordingMeta first.');
end
if frameIndex < 1 || frameIndex > sourceFiles.totalFrames
    error('LoadNpyRecordingFrame:Range','frameIndex=%d out of range [1,%d].',frameIndex,sourceFiles.totalFrames);
end

chunkIdx = find(frameIndex <= sourceFiles.frameEnds,1,'first');
prevEnd = 0;
if chunkIdx > 1
    prevEnd = sourceFiles.frameEnds(chunkIdx-1);
end
localIdx = frameIndex - prevEnd;

np = py.importlib.import_module('numpy');
pyArr = np.load(sourceFiles.framePaths{chunkIdx}, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
pySub = np.take(pyArr, int64(localIdx-1), int32(0));
im = localConvertPyArray(pySub);

if numel(sourceFiles.timeVecAll) >= frameIndex
    t = sourceFiles.timeVecAll(frameIndex);
else
    t = NaN;
end

exposureTimeUs = NaN;
if isfield(sourceFiles,'exposureTimesUs') && numel(sourceFiles.exposureTimesUs) >= frameIndex
    exposureTimeUs = double(sourceFiles.exposureTimesUs(frameIndex));
end
sequencerSetId = NaN;
if isfield(sourceFiles,'sequencerSetIds') && numel(sourceFiles.sequencerSetIds) >= frameIndex
    sequencerSetId = double(sourceFiles.sequencerSetIds(frameIndex));
end

[~,name,ext] = fileparts(sourceFiles.framePaths{chunkIdx});
frameName = sprintf('%s%s#%d',name,ext,localIdx);
end

function arr = localConvertPyArray(pyArr)
dtypeName = lower(char(py.str(pyArr.dtype.name)));
switch dtypeName
    case 'uint8', arr = uint8(pyArr);
    case 'uint16', arr = uint16(pyArr);
    case 'int16', arr = int16(pyArr);
    case 'int32', arr = int32(pyArr);
    case 'int64', arr = int64(pyArr);
    case {'single','float32'}, arr = single(pyArr);
    case {'double','float64'}, arr = double(pyArr);
    otherwise, arr = double(pyArr);
end
end
