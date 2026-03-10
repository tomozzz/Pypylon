function [rec, timeVecFile, info, sourceFiles] = LoadNpyRecording(recPath)
% LoadNpyRecording
% Loads full Python-captured SCOS recording from frames.npy / frames_*.npy

[timeVecFile, info, sourceFiles] = LoadNpyRecordingMeta(recPath);
[rawFrames, sourceFrameNames] = localReadFrameFiles(sourceFiles.framePaths);

rec = permute(rawFrames,[2 3 1]);
sourceFiles.frameNames = sourceFrameNames;
if isempty(sourceFiles.startDateTime)
    sourceFiles.startDateTime = datestr(now);
end
info.sourceFiles = sourceFiles;
end

function [rawFrames, sourceFrameNames] = localReadFrameFiles(framePaths)
rawFrames = [];
sourceFrameNames = {};
for i = 1:numel(framePaths)
    chunk = localReadWholeNpy(framePaths{i});
    if ndims(chunk) ~= 3
        error('LoadNpyRecording:BadShape','Frame file %s must be a 3D array, got %dD.',framePaths{i},ndims(chunk));
    end
    if isempty(rawFrames)
        rawFrames = chunk;
    else
        if size(chunk,2) ~= size(rawFrames,2) || size(chunk,3) ~= size(rawFrames,3)
            error('LoadNpyRecording:InconsistentShape', ...
                'Frame file %s has mismatched image size (%d,%d) vs (%d,%d).', ...
                framePaths{i},size(chunk,2),size(chunk,3),size(rawFrames,2),size(rawFrames,3));
        end
        rawFrames = cat(1,rawFrames,chunk);
    end
    [~,name,ext] = fileparts(framePaths{i});
    nChunk = size(chunk,1);
    sourceFrameNames = [sourceFrameNames; arrayfun(@(k) sprintf('%s%s#%d',name,ext,k), (1:nChunk)', 'UniformOutput', false)]; %#ok<AGROW>
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
    case 'uint8', arr = uint8(pyArr);
    case 'uint16', arr = uint16(pyArr);
    case 'int16', arr = int16(pyArr);
    case {'single','float32'}, arr = single(pyArr);
    case {'double','float64'}, arr = double(pyArr);
    otherwise, arr = double(pyArr);
end
end
