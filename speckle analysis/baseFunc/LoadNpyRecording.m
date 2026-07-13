function [rec, timeVecFile, info, sourceFiles] = LoadNpyRecording(recPath)
% LoadNpyRecording Load a complete single-file or chunked NPY recording.
%   REC is [H,W,N]. INFO contains full-length per-frame timestamp,
%   exposure-time, and sequencer-set vectors when those files exist.

[timeVecFile, info, sourceFiles] = LoadNpyRecordingMeta(recPath);
[rawFrames, sourceFrameNames] = localReadFrameFiles(sourceFiles.framePaths);

if size(rawFrames, 1) ~= sourceFiles.totalFrames
    error('LoadNpyRecording:FrameCountMismatch', ...
        'Loaded %d images; validated metadata describes %d.', ...
        size(rawFrames, 1), sourceFiles.totalFrames);
end
localValidateOptionalLength(info.timestampsCameraUs, ...
    sourceFiles.totalFrames, 'camera timestamps');
localValidateOptionalLength(info.exposureTimesUs, ...
    sourceFiles.totalFrames, 'exposure times');
localValidateOptionalLength(info.sequencerSetIds, ...
    sourceFiles.totalFrames, 'sequencer set IDs');

rec = permute(rawFrames, [2 3 1]);
sourceFiles.frameNames = sourceFrameNames;
if isempty(sourceFiles.startDateTime)
    sourceFiles.startDateTime = datestr(now);
end
info.sourceFiles = sourceFiles;
end


function localValidateOptionalLength(values, expectedCount, label)
if ~isempty(values) && numel(values) ~= expectedCount
    error('LoadNpyRecording:MetadataLengthMismatch', ...
        'Loaded %d %s values for %d frames.', ...
        numel(values), label, expectedCount);
end
end


function [rawFrames, sourceFrameNames] = localReadFrameFiles(framePaths)
rawFrames = [];
sourceFrameNames = {};
for i = 1:numel(framePaths)
    chunk = localReadWholeNpy(framePaths{i});
    if ndims(chunk) ~= 3
        error('LoadNpyRecording:BadShape', ...
            'Frame file %s must be a 3D (N,H,W) array.', framePaths{i});
    end
    if isempty(rawFrames)
        rawFrames = chunk;
    else
        if size(chunk, 2) ~= size(rawFrames, 2) || ...
                size(chunk, 3) ~= size(rawFrames, 3)
            error('LoadNpyRecording:InconsistentShape', ...
                ['Frame file %s has image size (%d,%d), ' ...
                 'expected (%d,%d).'], framePaths{i}, ...
                size(chunk, 2), size(chunk, 3), ...
                size(rawFrames, 2), size(rawFrames, 3));
        end
        rawFrames = cat(1, rawFrames, chunk);
    end
    [~, name, ext] = fileparts(framePaths{i});
    nChunk = size(chunk, 1);
    names = arrayfun(@(k) sprintf('%s%s#%d', name, ext, k), ...
        (1:nChunk)', 'UniformOutput', false);
    sourceFrameNames = [sourceFrameNames; names]; %#ok<AGROW>
end
end


function arr = localReadWholeNpy(filePath)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath, pyargs('allow_pickle', false));
arr = localConvertPyArray(pyArr);
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
