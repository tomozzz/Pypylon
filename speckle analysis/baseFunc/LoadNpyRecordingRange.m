function [rec, timeVecFile, info, sourceFiles] = LoadNpyRecordingRange(recPath, startFrame, nFrames)
% LoadNpyRecordingRange Load a 1-based range from an NPY recording.
%   REC is returned as [H,W,N]. Per-frame timestamps, exposure times, and
%   sequencer set IDs in INFO contain only the selected range. NFRAMES is
%   truncated at the end of the recording; Inf selects all remaining data.

if nargin < 2 || isempty(startFrame)
    startFrame = 1;
end
if nargin < 3 || isempty(nFrames)
    nFrames = Inf;
end

% Meta owns manifest resolution and strict cross-file validation. Passing
% the selection keeps large per-frame metadata lazy for range reads.
[timeVecFile, info, sourceFiles] = ...
    LoadNpyRecordingMeta(recPath, startFrame, nFrames);
startFrame = sourceFiles.selectionStartFrame;
nFrames = sourceFiles.selectionFrameCount;

[sourceFrameNames, localRanges] = localBuildFrameSelection( ...
    sourceFiles, startFrame, nFrames);
rawFrames = localReadFrameRanges( ...
    sourceFiles.framePaths, localRanges, sourceFiles.imageSize);
if size(rawFrames, 1) ~= nFrames
    error('LoadNpyRecordingRange:FrameCountMismatch', ...
        'Loaded %d images for a requested range of %d frames.', ...
        size(rawFrames, 1), nFrames);
end
rec = permute(rawFrames, [2 3 1]);

sourceFiles.frameNames = sourceFrameNames;
sourceFiles.startDateTime = '';
firstFinite = find(isfinite(timeVecFile), 1, 'first');
if ~isempty(firstFinite)
    sourceFiles.startDateTime = datestr(timeVecFile(firstFinite));
else
    sourceFiles.startDateTime = datestr(now);
end
info.nBits = localInferNBits(rawFrames);
info.sourceFiles = sourceFiles;
end


function [names, ranges] = localBuildFrameSelection(sourceFiles, startFrame, nFrames)
requestEnd = startFrame + nFrames - 1;
names = cell(nFrames, 1);
ranges = cell(numel(sourceFiles.framePaths), 1);
outIndex = 1;

for i = 1:numel(sourceFiles.framePaths)
    firstFrame = max(startFrame, sourceFiles.frameStarts(i));
    lastFrame = min(requestEnd, sourceFiles.frameEnds(i));
    if firstFrame > lastFrame
        continue;
    end
    localStart = firstFrame - sourceFiles.frameStarts(i) + 1;
    localCount = lastFrame - firstFrame + 1;
    ranges{i} = [localStart localCount];

    [~, name, ext] = fileparts(sourceFiles.framePaths{i});
    localIndices = localStart:(localStart + localCount - 1);
    chunkNames = arrayfun(@(idx) sprintf('%s%s#%d', name, ext, idx), ...
        localIndices(:), 'UniformOutput', false);
    names(outIndex:outIndex + localCount - 1) = chunkNames;
    outIndex = outIndex + localCount;
end

if outIndex ~= nFrames + 1 || any(cellfun(@isempty, names))
    error('LoadNpyRecordingRange:FrameCoverage', ...
        'Frame files do not completely cover the requested range %d-%d.', ...
        startFrame, requestEnd);
end
end


function rawFrames = localReadFrameRanges(framePaths, ranges, frameSize)
rawFrames = [];
for i = 1:numel(framePaths)
    if isempty(ranges{i})
        continue;
    end
    localStart = ranges{i}(1);
    localCount = ranges{i}(2);
    chunk = localReadNpyRange(framePaths{i}, localStart, localCount);
    if ndims(chunk) ~= 3
        error('LoadNpyRecordingRange:BadShape', ...
            'Selected data from %s is not a 3D (N,H,W) array.', framePaths{i});
    end
    if size(chunk, 2) ~= frameSize(1) || size(chunk, 3) ~= frameSize(2)
        error('LoadNpyRecordingRange:InconsistentShape', ...
            'Selected data from %s has an unexpected image size.', framePaths{i});
    end
    if isempty(rawFrames)
        rawFrames = chunk;
    else
        rawFrames = cat(1, rawFrames, chunk);
    end
end
if isempty(rawFrames)
    rawFrames = zeros([0 frameSize]);
end
end


function arr = localReadNpyRange(filePath, localStart, localCount)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
startZero = int64(localStart - 1);
stopZero = int64(localStart - 1 + localCount);
idx = np.arange(startZero, stopZero);
pySub = np.take(pyArr, idx, int32(0));
arr = localConvertPyArray(pySub);
end


function arr = localConvertPyArray(pyArr)
dtypeName = lower(char(py.str(pyArr.dtype.name)));
switch dtypeName
    case 'uint8'
        arr = uint8(pyArr);
    case 'uint16'
        arr = uint16(pyArr);
    case 'uint32'
        arr = uint32(pyArr);
    case 'uint64'
        arr = uint64(pyArr);
    case 'int8'
        arr = int8(pyArr);
    case 'int16'
        arr = int16(pyArr);
    case 'int32'
        arr = int32(pyArr);
    case 'int64'
        arr = int64(pyArr);
    case {'single', 'float32'}
        arr = single(pyArr);
    case {'double', 'float64'}
        arr = double(pyArr);
    otherwise
        arr = double(pyArr);
end
end


function nBits = localInferNBits(rawFrames)
if isa(rawFrames, 'uint8')
    nBits = 8;
    return;
end
maxVal = double(max(rawFrames(:)));
if maxVal <= 255
    nBits = 8;
elseif maxVal <= 1023
    nBits = 10;
elseif maxVal <= 4095
    nBits = 12;
else
    nBits = 16;
end
end
