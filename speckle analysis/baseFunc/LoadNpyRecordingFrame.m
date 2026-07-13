function [im, t, frameName, frameInfo] = LoadNpyRecordingFrame(recPath, frameIndex, sourceFiles)
% LoadNpyRecordingFrame Load one 1-based frame from an NPY recording.
%   The first three outputs are backward compatible. Optional FRAMEINFO
%   contains only this frame's exposure/timestamp/set metadata plus the
%   recording-level exposure mode and sequence.

if nargin < 3 || isempty(sourceFiles)
    error('LoadNpyRecordingFrame:MissingSource', ...
        'sourceFiles metadata is required. Call LoadNpyRecordingMeta first.');
end
if ~(isnumeric(frameIndex) && isscalar(frameIndex) && ...
        isfinite(frameIndex) && frameIndex == fix(frameIndex) && frameIndex >= 1)
    error('LoadNpyRecordingFrame:Range', ...
        'frameIndex must be a finite positive integer.');
end
if ~isfield(sourceFiles, 'totalFrames') || ...
        frameIndex > sourceFiles.totalFrames
    error('LoadNpyRecordingFrame:Range', ...
        'frameIndex=%d is outside the recording range.', frameIndex);
end

requiredFields = {'frameEnds', 'framePaths'};
for i = 1:numel(requiredFields)
    if ~isfield(sourceFiles, requiredFields{i})
        error('LoadNpyRecordingFrame:BadSource', ...
            'sourceFiles.%s is missing.', requiredFields{i});
    end
end

chunkIndex = find(frameIndex <= sourceFiles.frameEnds, 1, 'first');
if isempty(chunkIndex)
    error('LoadNpyRecordingFrame:FrameCoverage', ...
        'No frame chunk covers frameIndex=%d.', frameIndex);
end
previousEnd = 0;
if chunkIndex > 1
    previousEnd = sourceFiles.frameEnds(chunkIndex - 1);
end
localIndex = frameIndex - previousEnd;

np = py.importlib.import_module('numpy');
pyArr = np.load(sourceFiles.framePaths{chunkIndex}, ...
    pyargs('allow_pickle', false, 'mmap_mode', 'r'));
pySub = np.take(pyArr, int64(localIndex - 1), int32(0));
im = localConvertPyArray(pySub);

t = localSelectedValue(sourceFiles, 'timeVecAll', ...
    'timeVecSelection', frameIndex, NaN);
timestampsCameraUs = localSelectedValue(sourceFiles, ...
    'timestampsCameraUsAll', 'timestampsCameraUsSelection', frameIndex, []);
exposureTimesUs = localSelectedValue(sourceFiles, ...
    'exposureTimesUsAll', 'exposureTimesUsSelection', frameIndex, []);
sequencerSetIds = localSelectedValue(sourceFiles, ...
    'sequencerSetIdsAll', 'sequencerSetIdsSelection', frameIndex, []);

% sourceFiles from the normal Meta call contains all vectors. If a caller
% passes a range source that does not cover this frame, use the public lazy
% selection path rather than loading a complete metadata vector.
if (isnan(t) && localHasSource(sourceFiles, 'timestampSources')) || ...
        (isempty(exposureTimesUs) && localHasSource(sourceFiles, 'exposureSources')) || ...
        (isempty(sequencerSetIds) && localHasSource(sourceFiles, 'sequencerSetSources'))
    [lazyTime, lazyInfo] = LoadNpyRecordingMeta(recPath, frameIndex, 1);
    if isnan(t)
        t = lazyTime(1);
    end
    if isempty(timestampsCameraUs) && ~isempty(lazyInfo.timestampsCameraUs)
        timestampsCameraUs = lazyInfo.timestampsCameraUs(1);
    end
    if isempty(exposureTimesUs) && ~isempty(lazyInfo.exposureTimesUs)
        exposureTimesUs = lazyInfo.exposureTimesUs(1);
    end
    if isempty(sequencerSetIds) && ~isempty(lazyInfo.sequencerSetIds)
        sequencerSetIds = lazyInfo.sequencerSetIds(1);
    end
end

[~, name, ext] = fileparts(sourceFiles.framePaths{chunkIndex});
frameName = sprintf('%s%s#%d', name, ext, localIndex);

frameInfo = struct();
frameInfo.timestampsCameraUs = timestampsCameraUs;
frameInfo.exposureTimesUs = exposureTimesUs;
frameInfo.sequencerSetIds = sequencerSetIds;
if isfield(sourceFiles, 'exposureMode')
    frameInfo.exposureMode = sourceFiles.exposureMode;
else
    frameInfo.exposureMode = 'unknown';
end
if isfield(sourceFiles, 'exposureSequenceUs')
    frameInfo.exposureSequenceUs = sourceFiles.exposureSequenceUs;
else
    frameInfo.exposureSequenceUs = [];
end
end


function value = localSelectedValue(sourceFiles, allField, selectionField, frameIndex, missingValue)
value = missingValue;
if isfield(sourceFiles, allField)
    allValues = sourceFiles.(allField);
    if numel(allValues) >= frameIndex
        value = allValues(frameIndex);
        return;
    end
end
if isfield(sourceFiles, selectionField) && ...
        isfield(sourceFiles, 'selectionStartFrame') && ...
        isfield(sourceFiles, 'selectionFrameCount')
    selectionValues = sourceFiles.(selectionField);
    selectionEnd = sourceFiles.selectionStartFrame + ...
        sourceFiles.selectionFrameCount - 1;
    if frameIndex >= sourceFiles.selectionStartFrame && ...
            frameIndex <= selectionEnd && ~isempty(selectionValues)
        selectionIndex = frameIndex - sourceFiles.selectionStartFrame + 1;
        if numel(selectionValues) >= selectionIndex
            value = selectionValues(selectionIndex);
        end
    end
end
end


function tf = localHasSource(sourceFiles, fieldName)
tf = isfield(sourceFiles, fieldName) && ~isempty(sourceFiles.(fieldName));
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
