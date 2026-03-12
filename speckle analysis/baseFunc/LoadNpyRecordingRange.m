function [rec, timeVecFile, info, sourceFiles] = LoadNpyRecordingRange(recPath, startFrame, nFrames)
% LoadNpyRecordingRange
% Load a subset of Python-captured SCOS frames from .npy recordings.
%   startFrame : 1-based start index (default 1)
%   nFrames    : number of frames to read (default Inf)
%
% Returns:
%   rec        : [H,W,N] numeric (same dtype as source when possible)
%   timeVecFile: [N,1] timestamps for loaded frames (or NaN)
%   info       : metadata/info struct
%   sourceFiles: frame names + total frame count

if nargin < 2 || isempty(startFrame)
    startFrame = 1;
end
if nargin < 3 || isempty(nFrames)
    nFrames = Inf;
end

if isstring(recPath)
    recPath = char(recPath);
end

if exist(recPath,'dir') == 7
    folderPath = recPath;
elseif exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    folderPath = fileparts(recPath);
else
    error('LoadNpyRecordingRange:InvalidPath','Input must be a recording folder or .npy file.');
end

metadataPath = fullfile(folderPath,'metadata.json');
metadata = struct();
if exist(metadataPath,'file') == 2
    metadata = jsondecode(fileread(metadataPath));
end

framePaths = localResolveFramePaths(recPath, folderPath, metadata);
[frameCounts, frameSize] = localGetFrameInfo(framePaths);
totalFrames = sum(frameCounts);
if totalFrames < 1
    error('LoadNpyRecordingRange:NoFrames','No frames found in %s',folderPath);
end
if startFrame < 1 || startFrame > totalFrames
    error('LoadNpyRecordingRange:Range','startFrame must be in [1,%d], got %d.',totalFrames,startFrame);
end
if isinf(nFrames)
    nFrames = totalFrames - startFrame + 1;
end
nFrames = min(nFrames, totalFrames - startFrame + 1);

[sourceFrameNames, localRanges] = localBuildFrameSelection(framePaths, frameCounts, startFrame, nFrames);
rawFrames = localReadFrameRanges(framePaths, localRanges, frameSize);
rec = permute(rawFrames,[2 3 1]);

sourceFiles = struct();
sourceFiles.frameNames = sourceFrameNames;
sourceFiles.startDateTime = '';
sourceFiles.totalFrames = totalFrames;

fullTimeVec = localLoadTimeVec(folderPath, metadata, totalFrames);
idx = startFrame:(startFrame + nFrames - 1);
timeVecFile = fullTimeVec(idx);
if ~isempty(timeVecFile) && ~isnan(timeVecFile(1))
    sourceFiles.startDateTime = datestr(timeVecFile(1));
else
    sourceFiles.startDateTime = datestr(now);
end

info = struct();
info.fileType = '.npy';
info.imageSize = frameSize;
info.nBits = localInferNBits(rawFrames);
warnState = warning('off','all');
info.name = struct();
try
    info.name = GetParamsFromFileName(folderPath);
catch
    info.name = struct();
end
warning(warnState);

if isfield(metadata,'config')
    cfg = metadata.config;
    if isfield(cfg,'frame_rate_hz')
        info.name.FR = double(cfg.frame_rate_hz);
        info.cam.AcquisitionFrameRate = double(cfg.frame_rate_hz);
    elseif isfield(cfg,'acquisition_frame_rate')
        info.name.FR = double(cfg.acquisition_frame_rate);
        info.cam.AcquisitionFrameRate = double(cfg.acquisition_frame_rate);
    end
    if isfield(cfg,'black_level')
        info.name.BL = double(cfg.black_level);
    end
    if isfield(cfg,'gain')
        info.name.Gain = double(cfg.gain);
    end
    if isfield(cfg,'exposure_time')
        expT = double(cfg.exposure_time);
        if expT > 200
            expT = expT/1000;
        end
        info.name.expT = expT;
    end
end

if isfield(metadata,'dtype'); info.dtype = metadata.dtype; end
if isfield(metadata,'shape'); info.shape = metadata.shape; end
info.sourceFiles = sourceFiles;
end

function [frameCounts, frameSize] = localGetFrameInfo(framePaths)
np = py.importlib.import_module('numpy');
frameCounts = zeros(numel(framePaths),1);
frameSize = [];
for i = 1:numel(framePaths)
    arr = np.load(framePaths{i}, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
    shp = arr.shape;
    n = double(shp{1});
    h = double(shp{2});
    w = double(shp{3});
    frameCounts(i) = n;
    if isempty(frameSize)
        frameSize = [h w];
    elseif ~isequal(frameSize,[h w])
        error('LoadNpyRecordingRange:InconsistentShape','Frame shape mismatch in %s',framePaths{i});
    end
end
end

function [names, ranges] = localBuildFrameSelection(framePaths, frameCounts, startFrame, nFrames)
names = cell(nFrames,1);
ranges = cell(numel(framePaths),1);
remaining = nFrames;
globalStart = startFrame;
frameOffset = 0;
outIdx = 1;
for i = 1:numel(framePaths)
    n = frameCounts(i);
    chunkStart = frameOffset + 1;
    chunkEnd = frameOffset + n;
    if globalStart <= chunkEnd && remaining > 0
        localStart = max(1, globalStart - frameOffset);
        localCount = min(remaining, n - localStart + 1);
        ranges{i} = [localStart localCount];
        [~,name,ext] = fileparts(framePaths{i});
        chunkName = [name ext];
        k = localStart:(localStart+localCount-1);
        newNames = arrayfun(@(idx) sprintf('%s#%d',chunkName,idx), k(:), 'UniformOutput', false);
        names(outIdx:outIdx+localCount-1) = newNames;
        outIdx = outIdx + localCount;
        remaining = remaining - localCount;
        globalStart = chunkEnd + 1;
    end
    frameOffset = chunkEnd;
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
start0 = int64(localStart - 1);
stop0 = int64(localStart - 1 + localCount);
idx = np.arange(start0, stop0);
pySub = np.take(pyArr, idx, int32(0));
arr = localConvertPyArray(pySub);
end

function timeVecFile = localLoadTimeVec(folderPath, metadata, nOfFrames)
timeVecFile = nan([nOfFrames 1]);
camTsPath = fullfile(folderPath,'timestamps_camera_us.npy');
if exist(camTsPath,'file') == 2
    camUs = double(localReadWholeNpy(camTsPath));
    camUs = camUs(:);
    if numel(camUs) == nOfFrames
        if isfield(metadata,'capture_start_unix_s')
            tUnix = double(metadata.capture_start_unix_s) + camUs/1e6;
            dt = datetime(tUnix,'ConvertFrom','posixtime');
            timeVecFile = datenum(dt);
        else
            timeVecFile = camUs/1e6;
        end
    end
end
end

function arr = localReadWholeNpy(filePath)
np = py.importlib.import_module('numpy');
arr = localConvertPyArray(np.load(filePath, pyargs('allow_pickle', false)));
end

function arr = localConvertPyArray(pyArr)
dtypeName = lower(char(py.str(pyArr.dtype.name)));
switch dtypeName
    case 'uint8'
        arr = uint8(pyArr);
    case 'uint16'
        arr = uint16(pyArr);
    case 'int16'
        arr = int16(pyArr);
    case {'single','float32'}
        arr = single(pyArr);
    case {'double','float64'}
        arr = double(pyArr);
    otherwise
        arr = double(pyArr);
end
end

function framePaths = localResolveFramePaths(recPath, folderPath, metadata)
if exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    framePaths = {recPath};
    return;
end
framePaths = {};
if isfield(metadata,'frame_files') && ~isempty(metadata.frame_files)
    frameNames = metadata.frame_files;
    if ischar(frameNames) || isstring(frameNames)
        frameNames = cellstr(frameNames);
    end
    if iscell(frameNames)
        framePaths = cellfun(@(name) fullfile(folderPath, char(name)), frameNames, 'UniformOutput', false);
    end
end
if isempty(framePaths)
    defaultPath = fullfile(folderPath,'frames.npy');
    if exist(defaultPath,'file') == 2
        framePaths = {defaultPath};
    end
end
if isempty(framePaths)
    chunkFiles = dir(fullfile(folderPath,'frames_*.npy'));
    [~,sortIdx] = sort({chunkFiles.name});
    chunkFiles = chunkFiles(sortIdx);
    framePaths = arrayfun(@(f) fullfile(folderPath,f.name), chunkFiles, 'UniformOutput', false);
end
if isempty(framePaths)
    error('LoadNpyRecordingRange:MissingFrames','No frame .npy files were found in %s',folderPath);
end
end

function nBits = localInferNBits(rawFrames)
if isa(rawFrames,'uint8')
    nBits = 8;
elseif isa(rawFrames,'uint16')
    maxVal = double(max(rawFrames(:)));
    if maxVal <= 1023
        nBits = 10;
    elseif maxVal <= 4095
        nBits = 12;
    else
        nBits = 16;
    end
else
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
end
