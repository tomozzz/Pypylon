function [rec, timeVecFile, info, sourceFiles] = LoadNpyRecordingRange(recPath,startFrame,nFrames)
% LoadNpyRecordingRange Load a 1-based frame range and its aligned metadata.

if nargin < 2 || isempty(startFrame), startFrame = 1; end
if nargin < 3 || isempty(nFrames), nFrames = Inf; end
if startFrame ~= floor(startFrame) || startFrame < 1
    error('LoadNpyRecordingRange:Range','startFrame must be a positive integer.');
end
if ~isinf(nFrames) && (nFrames ~= floor(nFrames) || nFrames < 1)
    error('LoadNpyRecordingRange:Range','nFrames must be a positive integer or Inf.');
end

[fullTimeVec,info,fullSourceFiles] = LoadNpyRecordingMeta(recPath);
totalFrames = fullSourceFiles.totalFrames;
if startFrame > totalFrames
    error('LoadNpyRecordingRange:Range','startFrame must be in [1,%d], got %d.',totalFrames,startFrame);
end
if isinf(nFrames), nFrames = totalFrames-startFrame+1; end
nFrames = min(nFrames,totalFrames-startFrame+1);

[sourceFrameNames,localRanges] = localBuildFrameSelection( ...
    fullSourceFiles.framePaths,fullSourceFiles.frameCounts,startFrame,nFrames);
rawFrames = localReadFrameRanges(fullSourceFiles.framePaths,localRanges,fullSourceFiles.imageSize);
rec = permute(rawFrames,[2 3 1]);

idx = startFrame:(startFrame+nFrames-1);
timeVecFile = fullTimeVec(idx);
sourceFiles = fullSourceFiles;
sourceFiles.frameNames = sourceFrameNames;
sourceFiles.rangeStartFrame = startFrame;
sourceFiles.rangeEndFrame = startFrame+nFrames-1;
sourceFiles.timeVecAll = timeVecFile;
sourceFiles.timestampsCameraUs = localSlice(fullSourceFiles.timestampsCameraUs,idx);
sourceFiles.exposureTimesUs = localSlice(fullSourceFiles.exposureTimesUs,idx);
sourceFiles.sequencerSetIds = localSlice(fullSourceFiles.sequencerSetIds,idx);
if ~isempty(timeVecFile) && ~isnan(timeVecFile(1)) && timeVecFile(1) > 1e5
    sourceFiles.startDateTime = datestr(timeVecFile(1));
elseif isempty(sourceFiles.startDateTime)
    sourceFiles.startDateTime = datestr(now);
end

info.nBits = localInferNBits(rawFrames);
info.exposureTimesUs = sourceFiles.exposureTimesUs;
info.sequencerSetIds = sourceFiles.sequencerSetIds;
info.timestampsCameraUs = sourceFiles.timestampsCameraUs;
info.sourceFiles = sourceFiles;
end

function values = localSlice(values,idx)
if ~isempty(values), values = values(idx); end
end

function [names,ranges] = localBuildFrameSelection(framePaths,frameCounts,startFrame,nFrames)
names = cell(nFrames,1);
ranges = cell(numel(framePaths),1);
requestEnd = startFrame+nFrames-1;
frameOffset = 0;
outIdx = 1;
for i = 1:numel(framePaths)
    chunkStart = frameOffset+1;
    chunkEnd = frameOffset+frameCounts(i);
    overlapStart = max(startFrame,chunkStart);
    overlapEnd = min(requestEnd,chunkEnd);
    if overlapStart <= overlapEnd
        localStart = overlapStart-frameOffset;
        localCount = overlapEnd-overlapStart+1;
        ranges{i} = [localStart localCount];
        [~,name,ext] = fileparts(framePaths{i});
        k = localStart:(localStart+localCount-1);
        newNames = arrayfun(@(index) sprintf('%s%s#%d',name,ext,index), ...
            k(:),'UniformOutput',false);
        names(outIdx:outIdx+localCount-1) = newNames;
        outIdx = outIdx+localCount;
    end
    frameOffset = chunkEnd;
end
end

function rawFrames = localReadFrameRanges(framePaths,ranges,frameSize)
rawFrames = [];
for i = 1:numel(framePaths)
    if isempty(ranges{i}), continue; end
    chunk = localReadNpyRange(framePaths{i},ranges{i}(1),ranges{i}(2));
    if isempty(rawFrames), rawFrames = chunk;
    else, rawFrames = cat(1,rawFrames,chunk);
    end
end
if isempty(rawFrames), rawFrames = zeros([0 frameSize]); end
end

function arr = localReadNpyRange(filePath,localStart,localCount)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath,pyargs('allow_pickle',false,'mmap_mode','r'));
idx = np.arange(int64(localStart-1),int64(localStart-1+localCount));
arr = localConvertPyArray(np.take(pyArr,idx,int32(0)));
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

function nBits = localInferNBits(rawFrames)
if isa(rawFrames,'uint8'), nBits = 8; return; end
maxVal = double(max(rawFrames(:)));
if maxVal <= 255, nBits = 8;
elseif maxVal <= 1023, nBits = 10;
elseif maxVal <= 4095, nBits = 12;
else, nBits = 16;
end
end
