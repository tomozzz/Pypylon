%  ---------------------------------------------------------------------------------------------------------
%  [ timeVec,  , rawSpeckleContrast , rawSpeckleVar, corrSpeckleVar , corrSpeckleContrast, meanVec , info] = PlotSCOSvsTime(recName,windowSize,plotFlag,maskInput)
%  GUI mode:   - Choose the recording folder
%              - Choose widow size ( it will be used in stdfilter() function in order to calc the local std)
%              - Choose dark recording folder
%
%                First frame of the recording will appear, on witch the
%                user should draw a circle with the ROI (Region of Interest)
%                
%                In the second time this function will run for the same
%                recording , the ROI is already saved , so ne need to
%                choose it again.
%                Main and dark recording folder names should be in the following format :
%                <Name>_Gain<X>dB_expT<>ms_FR<X>Hz_BL<>DU 
%                Where expT -> exposure time in ms, FR -> Frame Rate, BL -> Black Level
%                If the dark recording is located in the same folder as the Main one, and starts with "background"
%                it is automatically recognized.
%
%  Command Mode: Same as GUI mode , but recName and windowSize variables must be specified. 
%                plotFlag - [optional] defualt= true                
%                maskInput - can be "true" (then all the image is taken as mask) or
%                a boolaen map the same size as the record.
%  ---------------------------------------------------------------------------------------------------------

function  [ timeVec, rawSpeckleContrast , corrSpeckleContrast, meanVec , info, results] = ...
    SCOSvsTime_WithNoiseSubtraction_Ver2(recName,backgroundName,windowSize,plotFlag,maskInput)
if nargin < 4
    plotFlag = true;
end
scriptDir = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDir,'baseFunc'))

%% Constants
timePeriodForP2P = 2; % [s]

%% Check input parameters
if nargin == 0 % GUI mode
    plotFlag = 1;
    if exist('.\lastRec.mat','file')
        lastF = load('.\lastRec.mat');        
    else
        lastF.recName = [ fileparts(pwd) '\Records' ];
    end
    
    [recName] = uigetdir(fileparts(lastF.recName));
    if recName == 0; return; end % if 'Cancel' was pressed
    hasFramesNpy = exist(fullfile(recName,'frames.npy'),'file') == 2;
    hasChunkFrames = ~isempty(dir(fullfile(recName,'frames_*.npy')));
    if ~(hasFramesNpy || hasChunkFrames)
        errordlg(['No frame .npy files found in ' recName ])
        error(['No frame .npy files found in ' recName ]);
    end
    
    save('.\lastRec.mat','recName')
    
    maxWindowSize = 50; minWindowSize = 3;
    answer = inputdlg('Window Size','',[1 25],{'7'});
    windowSize = str2double(answer{1});
    if isnan(windowSize) || windowSize > maxWindowSize || windowSize < minWindowSize
        errordlg(['Window Size must be a number between ' num2str(minWindowSize)  ' and ' num2str( num2str(maxWindowSize) ) ]);
        error(['Window Size must be a number between ' num2str(minWindowSize)  ' and ' num2str( num2str(maxWindowSize) ) ])
    end
    clear answer
end

if nargin == 0  || isempty(backgroundName)
    if exist([recName , '_dark'],'dir')
        backgroundName = [recName , '_dark'];
    else
        dir_Background = [ dir([fileparts(recName) , '\DarkIm*']) dir([fileparts(recName) , '\background*']) dir([fileparts(recName) , '\BG_*'])   ] ;
    
        if  isempty(dir_Background) || numel(dir_Background) > 1 
            backgroundName = uigetdir( fileparts(recName) ,'Please Select the background');
        else
            backgroundName = fullfile(fileparts(recName),dir_Background(1).name);
        end
        if isequal(backgroundName,0)
            disp('Aborting...')
            return;
        end
    end
end

%% Create Mask
upFolders = strsplit(recName,filesep);
rawName = strrep( strjoin(upFolders(max(1,end-2):end),'; '), '_',' '); %#ok<NASGU>

if exist(recName,'file') == 7 % it's a folder
    recSavePrefix = [ recName filesep ];
else % it's a file
    recSavePrefix = [ recName(1:find(recName=='.',1,'last')-1) '_' ];
end

isNpyRecord = exist(recName,'dir') == 7 && (exist(fullfile(recName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(recName,'frames_*.npy'))));

if isNpyRecord
    [timeVecMetadata, info, sourceFiles] = LoadNpyRecordingMeta(recName);
    nOfFrames = sourceFiles.totalFrames;

    perFrameExposureUs = [];
    if isfield(info,'exposureTimesUs')
        perFrameExposureUs = info.exposureTimesUs;
    end
    exposureSequenceUs = [];
    if isfield(info,'exposureSequenceUs')
        exposureSequenceUs = info.exposureSequenceUs;
    elseif isfield(info,'name') && isfield(info.name,'expT') && ...
            isnumeric(info.name.expT) && isscalar(info.name.expT) && isfinite(info.name.expT)
        exposureSequenceUs = double(info.name.expT) * 1000; % legacy info.name.expT is ms
    end
    [exposureGroupIndex, exposureGroupValuesUs, exposureGroupDetails] = ...
        GroupExposureFrames(perFrameExposureUs, exposureSequenceUs, nOfFrames);
    nExposureGroups = numel(exposureGroupValuesUs);
    isMultipleExposure = nExposureGroups > 1;

    sequencerSetIds = [];
    if isfield(info,'sequencerSetIds')
        sequencerSetIds = info.sequencerSetIds;
    end
    if isempty(sequencerSetIds)
        sequencerSetIds = nan(nOfFrames,1);
    else
        sequencerSetIds = double(sequencerSetIds(:));
        if numel(sequencerSetIds) ~= nOfFrames
            error('SCOSvsTime:SequencerSetLength', ...
                'sequencerSetIds contains %d values for %d frames.',numel(sequencerSetIds),nOfFrames);
        end
    end

    % A mixed-exposure preview would average different signal/noise regimes.
    % Use only the first exposure condition to define the common spatial ROI.
    previewIndices = find(exposureGroupIndex == 1);
    nPreview = min(20,numel(previewIndices));
    previewRec = zeros([sourceFiles.imageSize nPreview]);
    for k=1:nPreview
        previewRec(:,:,k) = double(LoadNpyRecordingFrame(recName,previewIndices(k),sourceFiles));
    end
    mean_frame = mean(previewRec,3);
    im1 = previewRec(:,:,1);
else
    error('SCOSvsTime_WithNoiseSubtraction_Ver2 now expects recName to be a folder containing frame .npy files');
end

maskFile = [recSavePrefix 'Mask.mat'];
if exist('maskInput','var')
    if isequal(maskInput, true)
        masks = {true(size(mean_frame))};
        totMask = masks{1};
        disp('Mask is the whole image')
    elseif iscell(maskInput)
        masks = maskInput;
        for k=1:numel(masks)
            if ~isequal( size(masks{k}), size(mean_frame) ) 
                error('wrong maskInput size, should be the same as the recording');
            end
        end
        totMask = masks{1};
        for k=2:numel(masks)
            totMask = totMask | masks{k};
        end
        disp('Input mask is a cell array')
    elseif islogical(maskInput)
        if ~isequal( size(maskInput), size(mean_frame) ) 
            error('wrong maskInput');
        end
        masks = {maskInput};
        totMask = masks{1};
        disp('Input single mask')
    else
        error('wrong maskInput type');
    end
    loadExistingFile_flag = 0;
else    
    if ~exist(maskFile,'file')
        loadExistingFile_flag = 0;    
    else
        if nargin == 0 % GUI mode
            answer = questdlg('Mask file already exist, do you want to define it again?','','Yes','No','No');
            loadExistingFile_flag = strcmp(answer,'No');
        else      % Command line mode -> load the saved mask 
            loadExistingFile_flag = 1;
        end
    end
end

% -- get ROI if needed and cut the margins 
ws2 = ceil(windowSize/2); % for margins marking as false
if ~exist('masks','var')
    if ~loadExistingFile_flag
        masks = {};
        channels.Centers = [];
        channels.Radii   = [];
        meanImForMask = mean_frame;
        addMore = true; ch = 1; figMask = [];
        while addMore
            [maskTemp , circ , figMask] = GetROI(meanImForMask,windowSize);
            masks{ch} = maskTemp; %#ok<AGROW>
            channels.Centers(ch,:) = circ.Center;
            channels.Radii(ch,1)   = circ.Radius;
            answer = questdlg('Add another ROI?','Channels','Yes','No','No');
            addMore = strcmp(answer,'Yes');
            ch = ch + 1;
        end
        totMask = masks{1};
        for k = 2:numel(masks)
            totMask = totMask | masks{k};
        end
        save(maskFile,'masks','channels','totMask');
        if ~isempty(figMask)
            savefig(figMask,[recName '\maskIm.fig'])
        end
    else
        M = load(maskFile);
        if isfield(M,'mask')
            masks{1} = false(size(M.mask));
            masks{1}(ws2+1:end-ws2,ws2+1:end-ws2) = ...
                M.mask(ws2+1:end-ws2,ws2+1:end-ws2);
            totMask = M.mask > 0;
            channels.Centers = M.circ.Center;
            channels.Radii  = M.circ.Radius;
        else
            load(maskFile); %#ok<LOAD>
        end
    end
end
for k=1:numel(masks)
    masks{k}( [ 1:ws2 (end-ws2+1):end ],:) = false;
    masks{k}( : , [ 1:ws2 (end-ws2+1):end ]) = false;
end
totMask( [ 1:ws2 (end-ws2+1):end ], : ) = false;
totMask( : , [ 1:ws2 (end-ws2+1):end ]) = false;

%% Check info
upFolders = strsplit(recName,filesep);
shortRecName = strjoin(upFolders(max(1,end-2):end)); %#ok<NASGU>

if ~isequal(backgroundName,0)
    if exist(backgroundName,'dir') == 7 && (exist(fullfile(backgroundName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(backgroundName,'frames_*.npy'))))
        [~,info_background] = LoadNpyRecordingMeta(backgroundName);
    else
        info_background = GetRecordInfo(backgroundName);
    end
    fields = {'Gain','BL'};
    if ~isMultipleExposure
        fields = [{'expT'} fields];
    end
    for fi = 1:numel(fields)
        param = fields{fi};
        if isfield(info_background,'name') && isfield(info_background.name,param) && ...
                isfield(info,'name') && isfield(info.name,param) && ...
                isnumeric(info_background.name.(param)) && isnumeric(info.name.(param)) && ...
                ~isnan(info_background.name.(param)) && ~isnan(info.name.(param)) && ...
                info_background.name.(param) ~= info.name.(param)
            error('Background.%s=%g   Record.%s=%g',param, info_background.name.(param), param, info.name.(param));
        end
    end
end

if isfield(info,'cam') && isfield(info.cam,'AcquisitionFrameRate')
    frameRate = info.cam.AcquisitionFrameRate;
else    
    if ~isfield(info.name,'FR') || isnan(info.name.FR)
        error('Frame Rate must be part of the recording name as "FR"');
    end
    frameRate = info.name.FR; 
end

[allTimeVec, usedCameraTimestamps] = BuildExposureTimeAxis(timeVecMetadata,nOfFrames,frameRate);
timeVecFile = timeVecMetadata;
if isempty(timeVecFile) || all(isnan(timeVecFile))
    % Preserve the legacy saved timeVecFile convention (1/frameRate origin),
    % while allTimeVec itself is normalized to zero by BuildExposureTimeAxis.
    timeVecFile = (1:nOfFrames)' ./ frameRate;
end
if usedCameraTimestamps
    info.timeAxisSource = 'camera_timestamp';
else
    info.timeAxisSource = 'frame_rate_fallback';
end

if ~isfield(info.name , 'BL' ) || ~isnumeric(info.name.BL) || isempty(info.name.BL)
    BlackLevel = 0;
else
    BlackLevel = info.name.BL;
end

%% Get Background and Background Noise
start_calib_time = tic;
disp('Load Background');
if ~exist(backgroundName,'file')
    error([backgroundName,' does not exist!']);
end
[backgroundByExposure, darkVarByExposure, darkCalibrationInfo] = ...
    localLoadDarkCorrections(backgroundName,info_background,mean_frame,recName, ...
        exposureGroupValuesUs,nExposureGroups);
darkVarPerWindowByExposure = cell(1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    darkVarPerWindowByExposure{exposureIdx} = ...
        imboxfilt(darkVarByExposure{exposureIdx},windowSize);
end

%% Get G[DU/e]
nOfBits = info.nBits;
actualGain = GetActualGain(info);
 
%% Calc spatialNoise 
spatialCalibration = localBuildSpatialCorrections(recName,sourceFiles, ...
    exposureGroupIndex,exposureGroupValuesUs,backgroundByExposure, ...
    BlackLevel,masks,totMask,windowSize,actualGain,plotFlag);

disp('Calibration Time')
toc(start_calib_time)

%% Decrease Image Size
[y,x] = find(totMask);
roi_lims  = [ min(y)-windowSize  , max(y)+windowSize
              min(x)-windowSize  , max(x)+windowSize ];

roi_lims( roi_lims < 1 ) = 1;        
if roi_lims(1,2) > info.imageSize(1)
    roi_lims(1,2) = info.imageSize(1);
end
if roi_lims(2,2) > info.imageSize(2)
    roi_lims(2,2) = info.imageSize(2);
end
roi.y = roi_lims(1,1):roi_lims(1,2);
roi.x = roi_lims(2,1):roi_lims(2,2);

masks_cut = cell(size(masks));
for ch = 1:numel(masks)    
    masks_cut{ch} = masks{ch}(roi.y  , roi.x); 
end

nOfChannels = numel(masks);
analysisCalibration = repmat(struct(),1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    analysisCalibration(exposureIdx).exposureTimeUs = exposureGroupValuesUs(exposureIdx);
    analysisCalibration(exposureIdx).background = backgroundByExposure{exposureIdx};
    analysisCalibration(exposureIdx).fitI_A_cut_byCh = cell(1,nOfChannels);
    analysisCalibration(exposureIdx).fitI_B_cut_byCh = cell(1,nOfChannels);
    for channelIdx = 1:nOfChannels
        analysisCalibration(exposureIdx).fitI_A_cut_byCh{channelIdx} = ...
            spatialCalibration(exposureIdx).fitI_A_byCh{channelIdx}(roi.y,roi.x);
        analysisCalibration(exposureIdx).fitI_B_cut_byCh{channelIdx} = ...
            spatialCalibration(exposureIdx).fitI_B_byCh{channelIdx}(roi.y,roi.x);
    end
    analysisCalibration(exposureIdx).spVar_cut = ...
        spatialCalibration(exposureIdx).spVar(roi.y,roi.x);
    analysisCalibration(exposureIdx).darkVarPerWindow_cut = ...
        darkVarPerWindowByExposure{exposureIdx}(roi.y,roi.x);
end

%% Calc Specle Contrast
disp(['Calculating SCOS on "' recName '" ... ']);
disp(['Mono' num2str(nOfBits)]);
frameNames = cell(nOfFrames,1);

im1 = double(im1);

devide_by = 1;
if nOfBits == 12  && all(mod(im1(:),2^4) == 0)
    devide_by = 2^4;
elseif nOfBits == 10  && all(mod(im1(:),2^6) == 0)
    devide_by = 2^6;
end

seriesTemplate = struct('frameIndices',[],'frameNames',{{}}, ...
    'rawSpeckleContrast',[],'corrSpeckleContrast',[],'meanIntensity',[], ...
    'writeCount',0);
exposureSeries = repmat(seriesTemplate,1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    indices = find(exposureGroupIndex == exposureIdx);
    nSeriesFrames = numel(indices);
    exposureSeries(exposureIdx).frameIndices = indices;
    exposureSeries(exposureIdx).frameNames = cell(nSeriesFrames,1);
    exposureSeries(exposureIdx).rawSpeckleContrast = nan(nSeriesFrames,nOfChannels);
    exposureSeries(exposureIdx).corrSpeckleContrast = nan(nSeriesFrames,nOfChannels);
    exposureSeries(exposureIdx).meanIntensity = nan(nSeriesFrames,nOfChannels);
end

start_scos = tic;

batchSize = 1000;
for batchStart = 1:batchSize:nOfFrames
    batchCount = min(batchSize, nOfFrames - batchStart + 1);
    [batchRec,~,~,batchSourceFiles] = LoadNpyRecordingRange(recName,batchStart,batchCount);

    for j = 1:batchCount
        i = batchStart + j - 1;

        if i == 50
            time50frames = toc(start_scos);
            fprintf('\n Estimated Time = %g min (%d frames)\n',round(time50frames/50*nOfFrames/60,2), nOfFrames)
        end
        if mod(i,200) == 0 
            fprintf('%d\t',i);
            if mod(i,2000) == 0
                fprintf('\n');
            end
        end

        frameNames{i} = batchSourceFiles.frameNames{j};
        exposureIdx = exposureGroupIndex(i);
        seriesPosition = exposureSeries(exposureIdx).writeCount + 1;
        [rawRow,corrRow,meanRow] = localCalculateScosFrame( ...
            batchRec(:,:,j),devide_by,BlackLevel,analysisCalibration(exposureIdx), ...
            roi,masks_cut,windowSize,actualGain);
        exposureSeries(exposureIdx).rawSpeckleContrast(seriesPosition,:) = rawRow;
        exposureSeries(exposureIdx).corrSpeckleContrast(seriesPosition,:) = corrRow;
        exposureSeries(exposureIdx).meanIntensity(seriesPosition,:) = meanRow;
        exposureSeries(exposureIdx).frameNames{seriesPosition} = frameNames{i};
        exposureSeries(exposureIdx).writeCount = seriesPosition;

        if seriesPosition == 1
            fprintf('[EXPOSURE %.12g us] <I>=%.3g DU, K_raw=%.5g, K_corr=%.5g\n', ...
                exposureGroupValuesUs(exposureIdx),meanRow(1),rawRow(1),corrRow(1));
        end
    end

    clear batchRec batchSourceFiles
end
fprintf('\n');

%% Build exposure-separated results
if isfield(info,'exposureMode') && ~isempty(info.exposureMode)
    results.exposureMode = char(info.exposureMode);
elseif isMultipleExposure
    results.exposureMode = 'sequencer';
else
    results.exposureMode = 'fixed';
end
results.exposureSequenceUs = exposureSequenceUs;
results.timeAxisSource = info.timeAxisSource;
results.unusedExposureSequenceUs = exposureGroupDetails.unusedSequenceUs;
results.darkCalibration = darkCalibrationInfo;
results.byExposure = struct([]);

for exposureIdx = 1:nExposureGroups
    indices = exposureSeries(exposureIdx).frameIndices;
    exposureTimeVec = allTimeVec(indices);
    corrMatrix = exposureSeries(exposureIdx).corrSpeckleContrast;
    bfiMatrix = 1 ./ corrMatrix;
    rbfiMatrix = localCalculateRelativeBFI(bfiMatrix,exposureTimeVec);

    actualExposureUs = [];
    if ~isempty(perFrameExposureUs)
        actualExposureUs = double(perFrameExposureUs(indices));
        actualExposureUs = actualExposureUs(:);
    elseif isfinite(exposureGroupValuesUs(exposureIdx))
        actualExposureUs = repmat(exposureGroupValuesUs(exposureIdx),numel(indices),1);
    end

    exposureResult = struct();
    exposureResult.exposureTimeUs = exposureGroupDetails.actualMedianUs(exposureIdx);
    exposureResult.requestedExposureTimeUs = exposureGroupValuesUs(exposureIdx);
    exposureResult.actualExposureTimesUs = actualExposureUs;
    exposureResult.frameIndices = indices;
    exposureResult.sequencerSetIds = sequencerSetIds(indices);
    if all(isnan(exposureResult.sequencerSetIds))
        exposureResult.sequencerSetIds = [];
    end
    exposureResult.timeVec = exposureTimeVec;
    exposureResult.rawSpeckleContrast = exposureSeries(exposureIdx).rawSpeckleContrast;
    exposureResult.corrSpeckleContrast = corrMatrix;
    exposureResult.BFI = bfiMatrix;
    exposureResult.rBFI = rbfiMatrix;
    exposureResult.meanIntensity = exposureSeries(exposureIdx).meanIntensity;
    exposureResult.frameNames = exposureSeries(exposureIdx).frameNames;
    if numel(exposureTimeVec) > 1 && median(diff(exposureTimeVec)) > 0
        exposureResult.effectiveFrameRateHz = 1 / median(diff(exposureTimeVec));
    else
        exposureResult.effectiveFrameRateHz = NaN;
    end
    if exposureIdx == 1
        results.byExposure = exposureResult;
    else
        results.byExposure(exposureIdx) = exposureResult;
    end
end

if ~isMultipleExposure
    timeVec = results.byExposure(1).timeVec;
    rawSpeckleContrast = localMatrixColumnsToCells(results.byExposure(1).rawSpeckleContrast);
    corrSpeckleContrast = localMatrixColumnsToCells(results.byExposure(1).corrSpeckleContrast);
    meanVec = localMatrixColumnsToCells(results.byExposure(1).meanIntensity);
    BFI_matrix = results.byExposure(1).BFI;
    meanI_matrix = results.byExposure(1).meanIntensity;
    p2p_time = timeVec<timePeriodForP2P; %#ok<NASGU>
else
    % The legacy outputs cannot represent multiple exposure-specific clocks
    % without interleaving incompatible conditions. Use results.byExposure.
    timeVec = [];
    rawSpeckleContrast = {};
    corrSpeckleContrast = {};
    meanVec = {};
    BFI_matrix = [];
    meanI_matrix = [];
    warning('SCOSvsTime:MultipleExposureResults', ...
        ['Multiple exposure conditions were analyzed separately. Legacy time-series ' ...
         'outputs are empty; use results.byExposure.']);
end

%% Save
stdStr = sprintf('Std%dx%d',windowSize,windowSize);
if exist([recSavePrefix 'Local' stdStr '.mat'],'file')
    delete([recSavePrefix 'Local' stdStr '.mat']);
end % just for it to have the right date

startDateTime = sourceFiles.startDateTime;
if isempty(startDateTime)
    startDateTime = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
end

if ~exist('channels','var')
    channels = struct('Centers',[],'Radii',[]);
end
results.channels = channels;

if ~isMultipleExposure
    % Preserve all legacy variables and file names for fixed/single-condition
    % recordings. The additional results variable is backward compatible.
    save([recSavePrefix 'Local' stdStr '_corr.mat'], ...
        'startDateTime','timeVec', 'corrSpeckleContrast' , 'rawSpeckleContrast', ...
        'meanVec', 'info','nOfChannels', 'recName','windowSize','timeVecFile', ...
        'frameNames','results');

    BFI_output = struct('timeVec',timeVec,'BFI',BFI_matrix,'meanI',meanI_matrix, ...
        'channels',channels,'results',results);
    save([recSavePrefix 'BFI_output.mat'],'-struct','BFI_output');

    for ch = 1:nOfChannels
        singleBFI = struct();
        singleBFI.timeVec = timeVec;
        singleBFI.BFI = BFI_matrix(:,ch);
        singleBFI.meanI = meanI_matrix(:,ch);
        singleBFI.results = localSelectResultChannel(results,ch);
        save([recSavePrefix sprintf('BFI_Ch%d.mat',ch)],'-struct','singleBFI');
    end
else
    % An interleaved legacy matrix would invite invalid cross-exposure
    % analysis. Multi-exposure MAT files expose results.byExposure only.
    save([recSavePrefix 'Local' stdStr '_corr.mat'], ...
        'startDateTime','results','info','nOfChannels','recName','windowSize', ...
        'timeVecFile','frameNames');
    BFI_output = struct('results',results,'channels',channels);
    save([recSavePrefix 'BFI_output.mat'],'-struct','BFI_output');
    for ch = 1:nOfChannels
        singleBFI = struct('results',localSelectResultChannel(results,ch));
        save([recSavePrefix sprintf('BFI_Ch%d.mat',ch)],'-struct','singleBFI');
    end
end

%% Plot exposure-separated results
if plotFlag
    localPlotExposureResults(results,recName,recSavePrefix,stdStr,isMultipleExposure);
end

%%
toc(start_scos)
end

function [backgroundByExposure, darkVarByExposure, calibrationInfo] = ...
        localLoadDarkCorrections(backgroundName,infoBackground,meanFrame,recName, ...
            exposureGroupValuesUs,nExposureGroups)
% Dark data recorded at several exposures are never averaged together.
% If only one Dark condition (or an old Dark recording without exposure
% metadata) exists, it is reused deliberately and recorded as a limitation.

requiredBackgroundFrames = 400;
backgroundByExposure = cell(1,nExposureGroups);
darkVarByExposure = cell(1,nExposureGroups);
calibrationInfo = repmat(struct('sourceExposureTimeUs',NaN, ...
    'sharedAcrossExposure',false,'frameCount',0,'source',backgroundName),1,nExposureGroups);

isNpyBackground = exist(backgroundName,'dir') == 7 && ...
    (exist(fullfile(backgroundName,'frames.npy'),'file') == 2 || ...
     ~isempty(dir(fullfile(backgroundName,'frames_*.npy'))));

if isNpyBackground
    [~,backgroundInfo,backgroundSourceFiles] = LoadNpyRecordingMeta(backgroundName);
    backgroundExposureTimesUs = [];
    if isfield(backgroundInfo,'exposureTimesUs')
        backgroundExposureTimesUs = backgroundInfo.exposureTimesUs;
    end
    backgroundSequenceUs = [];
    if isfield(backgroundInfo,'exposureSequenceUs')
        backgroundSequenceUs = backgroundInfo.exposureSequenceUs;
    elseif isfield(backgroundInfo,'name') && isfield(backgroundInfo.name,'expT') && ...
            isnumeric(backgroundInfo.name.expT) && isscalar(backgroundInfo.name.expT) && ...
            isfinite(backgroundInfo.name.expT)
        backgroundSequenceUs = double(backgroundInfo.name.expT) * 1000;
    end
    [backgroundGroups,backgroundGroupValuesUs,backgroundGroupDetails] = ...
        GroupExposureFrames(backgroundExposureTimesUs,backgroundSequenceUs, ...
            backgroundSourceFiles.totalFrames);

    backgroundBlackLevel = localInfoBlackLevel(backgroundInfo);
    if isscalar(backgroundGroupValuesUs)
        indices = find(backgroundGroups == 1);
        [sharedBackground,sharedDarkVar] = localReadNpyDarkStatistics( ...
            backgroundName,backgroundSourceFiles,indices,requiredBackgroundFrames, ...
            backgroundBlackLevel);
        [sharedBackground,sharedDarkVar] = localAlignDarkSize( ...
            sharedBackground,sharedDarkVar,meanFrame,recName);
        for exposureIdx = 1:nExposureGroups
            backgroundByExposure{exposureIdx} = sharedBackground;
            darkVarByExposure{exposureIdx} = sharedDarkVar;
            calibrationInfo(exposureIdx).sourceExposureTimeUs = ...
                backgroundGroupDetails.actualMedianUs(1);
            calibrationInfo(exposureIdx).sharedAcrossExposure = nExposureGroups > 1;
            calibrationInfo(exposureIdx).frameCount = requiredBackgroundFrames;
        end
        if nExposureGroups > 1
            localWarnSharedDarkCorrection();
        end
        return;
    end

    for exposureIdx = 1:nExposureGroups
        matchingBackgroundGroup = localFindExposureMatch( ...
            exposureGroupValuesUs(exposureIdx),backgroundGroupValuesUs);
        if isempty(matchingBackgroundGroup)
            error('SCOSvsTime:MissingDarkExposure', ...
                ['Dark recording has no condition matching exposure %.12g us. ' ...
                 'Different Dark exposures will not be averaged as a fallback.'], ...
                exposureGroupValuesUs(exposureIdx));
        end
        indices = find(backgroundGroups == matchingBackgroundGroup);
        [background,darkVar] = localReadNpyDarkStatistics( ...
            backgroundName,backgroundSourceFiles,indices,requiredBackgroundFrames, ...
            backgroundBlackLevel);
        [background,darkVar] = localAlignDarkSize(background,darkVar,meanFrame,recName);
        backgroundByExposure{exposureIdx} = background;
        darkVarByExposure{exposureIdx} = darkVar;
        calibrationInfo(exposureIdx).sourceExposureTimeUs = ...
            backgroundGroupDetails.actualMedianUs(matchingBackgroundGroup);
        calibrationInfo(exposureIdx).frameCount = requiredBackgroundFrames;
    end
    return;
end

% Legacy TIFF/AVI/MAT Dark recordings do not carry per-frame exposure data.
% Preserve their established loading path, then reuse the one correction for
% every exposure with an explicit warning and metadata flag.
[background,darkVar,nBackgroundFrames] = localLoadLegacyDark( ...
    backgroundName,infoBackground,requiredBackgroundFrames);
[background,darkVar] = localAlignDarkSize(background,darkVar,meanFrame,recName);
for exposureIdx = 1:nExposureGroups
    backgroundByExposure{exposureIdx} = background;
    darkVarByExposure{exposureIdx} = darkVar;
    calibrationInfo(exposureIdx).sharedAcrossExposure = nExposureGroups > 1;
    calibrationInfo(exposureIdx).frameCount = nBackgroundFrames;
end
if nExposureGroups > 1
    localWarnSharedDarkCorrection();
end
end

function [background,darkVar] = localReadNpyDarkStatistics( ...
        backgroundName,sourceFiles,indices,requiredFrames,blackLevel)
if numel(indices) < requiredFrames
    error('SCOSvsTime:NotEnoughDarkFrames', ...
        'Dark exposure condition requires %d frames, but only %d were captured.', ...
        requiredFrames,numel(indices));
end
selected = indices(1:requiredFrames);
darkRecord = zeros([sourceFiles.imageSize requiredFrames]);
for frameIdx = 1:requiredFrames
    darkRecord(:,:,frameIdx) = double(LoadNpyRecordingFrame( ...
        backgroundName,selected(frameIdx),sourceFiles));
end
background = mean(darkRecord,3) - blackLevel;
darkVar = std(darkRecord,0,3).^2;
end

function [background,darkVar,nBackgroundFrames] = localLoadLegacyDark( ...
        backgroundName,infoBackground,requiredFrames)
blackLevel = localInfoBlackLevel(infoBackground);
if exist(backgroundName,'dir') == 7
    meanPath = fullfile(backgroundName,'meanIm.mat');
    if exist(meanPath,'file') == 2
        backgroundStruct = load(meanPath);
        if isfield(backgroundStruct,'nOfFrames')
            nBackgroundFrames = backgroundStruct.nOfFrames;
        else
            nBackgroundFrames = GetNumOfFrames(backgroundName);
        end
        if nBackgroundFrames < requiredFrames
            error('SCOSvsTime:NotEnoughDarkFrames', ...
                'Not enough Dark frames. Required %d, found %d.',requiredFrames,nBackgroundFrames);
        end
        if isfield(backgroundStruct,'recMean') && isfield(backgroundStruct,'recVar')
            background = backgroundStruct.recMean - blackLevel;
            darkVar = backgroundStruct.recVar;
        else
            [background,darkVar] = ReadRecordVarAndMean(backgroundName);
            background = background - blackLevel;
        end
    else
        nBackgroundFrames = GetNumOfFrames(backgroundName);
        if nBackgroundFrames < requiredFrames
            error('SCOSvsTime:NotEnoughDarkFrames', ...
                'Not enough Dark frames. Required %d, found %d.',requiredFrames,nBackgroundFrames);
        end
        [background,darkVar] = ReadRecordVarAndMean(backgroundName);
        background = background - blackLevel;
    end
elseif endsWith(lower(backgroundName),'.mat')
    backgroundStruct = load(backgroundName);
    names = fieldnames(backgroundStruct);
    if isfield(backgroundStruct,'recMean') && isfield(backgroundStruct,'recVar')
        background = backgroundStruct.recMean - blackLevel;
        darkVar = backgroundStruct.recVar;
        nBackgroundFrames = requiredFrames;
    else
        videoField = find(startsWith(names,'Video'),1,'first');
        if isempty(videoField)
            error('SCOSvsTime:InvalidDarkMat', ...
                'Dark MAT file must contain recMean/recVar or a Video* array.');
        end
        darkRecord = double(backgroundStruct.(names{videoField}));
        nBackgroundFrames = size(darkRecord,3);
        if nBackgroundFrames < requiredFrames
            error('SCOSvsTime:NotEnoughDarkFrames', ...
                'Not enough Dark frames. Required %d, found %d.',requiredFrames,nBackgroundFrames);
        end
        background = mean(darkRecord,3) - blackLevel;
        darkVar = std(darkRecord,0,3).^2;
    end
else
    error('SCOSvsTime:InvalidDarkPath','Unsupported Dark recording: %s',backgroundName);
end

if abs(mean(background(:),'omitnan')) > 3
    warning('SCOSvsTime:SuspiciousDarkLevel', ...
        'Suspicious mean Dark background level %.3g DU.',mean(background(:),'omitnan'));
end
end

function [background,darkVar] = localAlignDarkSize(background,darkVar,meanFrame,recName)
if isequal(size(background),size(meanFrame)) && isequal(size(darkVar),size(meanFrame))
    return;
end

roiPath = fullfile(recName,'ROI.mat');
if exist(roiPath,'file') == 2
    roiStruct = load(roiPath);
    if isfield(roiStruct,'xLimits') && isfield(roiStruct,'yLimits') && ...
            roiStruct.xLimits(1) >= 1 && roiStruct.yLimits(1) >= 1 && ...
            roiStruct.xLimits(end) <= size(background,2) && ...
            roiStruct.yLimits(end) <= size(background,1)
        background = background(roiStruct.yLimits(1):roiStruct.yLimits(2), ...
            roiStruct.xLimits(1):roiStruct.xLimits(2));
        darkVar = darkVar(roiStruct.yLimits(1):roiStruct.yLimits(2), ...
            roiStruct.xLimits(1):roiStruct.xLimits(2));
    end
end

if ~isequal(size(background),size(meanFrame)) || ~isequal(size(darkVar),size(meanFrame))
    error('SCOSvsTime:DarkImageSize', ...
        'Dark image size [%s] does not match recording image size [%s].', ...
        num2str(size(background)),num2str(size(meanFrame)));
end
end

function blackLevel = localInfoBlackLevel(info)
blackLevel = 0;
if isfield(info,'name') && isfield(info.name,'BL') && isnumeric(info.name.BL) && ...
        isscalar(info.name.BL) && isfinite(info.name.BL)
    blackLevel = double(info.name.BL);
end
end

function localWarnSharedDarkCorrection()
warning('SCOSvsTime:SharedDarkCorrection', ...
    ['A single Dark/noise correction is being reused for multiple exposure ' ...
     'conditions. Intensity and noise depend on exposure time; rigorous ' ...
     'comparison requires Dark data acquired separately at each exposure.']);
end

function matchingGroup = localFindExposureMatch(value,candidates)
matchingGroup = [];
if ~isfinite(value) || isempty(candidates)
    return;
end
try
    [groupIndex,~,details] = GroupExposureFrames(value,candidates,1);
    matchingGroup = find(details.sequenceToGroup == groupIndex(1),1,'first');
catch err
    if ~strcmp(err.identifier,'GroupExposureFrames:UnmatchedExposure')
        rethrow(err);
    end
end
end

function spatialCalibration = localBuildSpatialCorrections(recName,sourceFiles, ...
        exposureGroupIndex,exposureGroupValuesUs,backgroundByExposure, ...
        blackLevel,masks,totMask,windowSize,actualGain,plotFlag)
% Spatial coefficients are estimated independently for every applied
% exposure. Averaging alternating exposures here would mix both intensity
% and exposure-dependent noise before SCOS is calculated.

nExposureGroups = numel(exposureGroupValuesUs);
calibrationVersion = 2;
if nExposureGroups == 1
    cachePath = fullfile(recName,'smoothingCoefficients.mat');
else
    cachePath = fullfile(recName,'smoothingCoefficientsByExposure.mat');
end
if exist(cachePath,'file') == 2
    cached = load(cachePath);
    [cacheIsValid,cacheOrder] = localValidateSpatialCache(cached,calibrationVersion, ...
        sourceFiles.imageSize,windowSize,masks,exposureGroupValuesUs,actualGain);
    if cacheIsValid
        if nExposureGroups == 1
            disp('Load ROI-specific Spatial Noise and Smoothing Coefficients');
        else
            disp('Load exposure- and ROI-specific Spatial Noise and Smoothing Coefficients');
        end
        spatialCalibration = cached.spatialCalibration(cacheOrder);
        return;
    end
    warning('SCOSvsTime:StaleSpatialCache', ...
        ['Ignoring an incompatible spatial-calibration cache. The cache will be ' ...
         'recomputed with ROI-specific intensity fits and spatial shot-noise subtraction.']);
end

disp('Calc exposure- and ROI-specific Spatial Noise and Smoothing Coefficients');
spatialCalibration = repmat(struct(),1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    availableIndices = find(exposureGroupIndex == exposureIdx);
    desiredFrames = 600;
    if numel(availableIndices) > 1000
        desiredFrames = 1000;
    end
    nSpatialFrames = min(desiredFrames,numel(availableIndices));
    if nSpatialFrames < 2
        error('SCOSvsTime:NotEnoughSpatialFrames', ...
            'Exposure %.12g us requires at least two frames for spatial calibration.', ...
            exposureGroupValuesUs(exposureIdx));
    end
    if nSpatialFrames < desiredFrames
        warning('SCOSvsTime:FewSpatialFrames', ...
            'Exposure %.12g us uses only %d frames for spatial calibration.', ...
            exposureGroupValuesUs(exposureIdx),nSpatialFrames);
    end

    selected = availableIndices(1:nSpatialFrames);
    spatialRecord = zeros([sourceFiles.imageSize nSpatialFrames]);
    for frameIdx = 1:nSpatialFrames
        spatialRecord(:,:,frameIdx) = double(LoadNpyRecordingFrame( ...
            recName,selected(frameIdx),sourceFiles));
    end
    spatialRecord = spatialRecord - blackLevel;
    spatialImage = mean(spatialRecord,3) - backgroundByExposure{exposureIdx};
    spatialVarianceRaw = stdfilt(spatialImage,true(windowSize)).^2;
    spatialShotVariance = actualGain .* imboxfilt(spatialImage,windowSize) ./ nSpatialFrames;
    spatialVariance = max(spatialVarianceRaw - spatialShotVariance,0);
    fitI_A_byCh = cell(1,numel(masks));
    fitI_B_byCh = cell(1,numel(masks));
    for channelIdx = 1:numel(masks)
        [fitI_A_byCh{channelIdx},fitI_B_byCh{channelIdx}] = ...
            FitMeanIm(spatialRecord,masks{channelIdx},windowSize);
    end

    spatialCalibration(exposureIdx).exposureTimeUs = exposureGroupValuesUs(exposureIdx);
    spatialCalibration(exposureIdx).spVar = spatialVariance;
    spatialCalibration(exposureIdx).spVarRaw = spatialVarianceRaw;
    spatialCalibration(exposureIdx).spShotVar = spatialShotVariance;
    spatialCalibration(exposureIdx).fitI_A_byCh = fitI_A_byCh;
    spatialCalibration(exposureIdx).fitI_B_byCh = fitI_B_byCh;
    spatialCalibration(exposureIdx).spIm = spatialImage;
    spatialCalibration(exposureIdx).frameCount = nSpatialFrames;

    if plotFlag
        spatialFigure = my_imagesc(spatialImage);
        title(sprintf('Image average: %d frames, exposure %.12g us', ...
            nSpatialFrames,exposureGroupValuesUs(exposureIdx)));
        if nExposureGroups == 1
            figureName = 'spIm.fig';
        else
            figureName = sprintf('spIm_exp%sus.fig', ...
                localExposureFileLabel(exposureGroupValuesUs(exposureIdx)));
        end
        savefig(spatialFigure,fullfile(recName,figureName));
    end
end
savedCalibrationVersion = calibrationVersion;
savedWindowSize = windowSize;
savedMasks = masks;
savedMask = totMask;
savedExposureValuesUs = exposureGroupValuesUs;
savedActualGain = actualGain;
save(cachePath,'spatialCalibration','savedCalibrationVersion','savedWindowSize', ...
    'savedMasks','savedMask','savedExposureValuesUs','savedActualGain');
end

function [isValid,cacheOrder] = localValidateSpatialCache(cached,expectedVersion, ...
        imageSize,windowSize,masks,exposureValuesUs,actualGain)
isValid = false;
cacheOrder = [];
required = {'spatialCalibration','savedCalibrationVersion','savedWindowSize', ...
    'savedMasks','savedExposureValuesUs','savedActualGain'};
if ~all(isfield(cached,required)) || ...
        ~isnumeric(cached.savedCalibrationVersion) || ...
        ~isscalar(cached.savedCalibrationVersion) || ...
        cached.savedCalibrationVersion ~= expectedVersion || ...
        ~isnumeric(cached.savedWindowSize) || ~isscalar(cached.savedWindowSize) || ...
        cached.savedWindowSize ~= windowSize || ...
        ~iscell(cached.savedMasks) || ...
        ~isequal(cached.savedMasks,masks) || ...
        ~isnumeric(cached.savedActualGain) || ~isscalar(cached.savedActualGain) || ...
        ~isequaln(cached.savedActualGain,actualGain) || ...
        ~isnumeric(cached.savedExposureValuesUs) || ...
        numel(cached.savedExposureValuesUs) ~= numel(exposureValuesUs) || ...
        numel(cached.spatialCalibration) ~= numel(exposureValuesUs)
    return;
end

cacheOrder = zeros(1,numel(exposureValuesUs));
for exposureIdx = 1:numel(exposureValuesUs)
    matchingCacheExposure = localFindExposureMatch( ...
        exposureValuesUs(exposureIdx),cached.savedExposureValuesUs);
    if isempty(matchingCacheExposure) || matchingCacheExposure < 1
        cacheOrder = [];
        return;
    end
    cacheOrder(exposureIdx) = matchingCacheExposure;
end
if numel(unique(cacheOrder)) ~= numel(cacheOrder)
    cacheOrder = [];
    return;
end

for exposureIdx = 1:numel(cacheOrder)
    calibration = cached.spatialCalibration(cacheOrder(exposureIdx));
    requiredCalibration = {'spVar','spVarRaw','spShotVar','fitI_A_byCh', ...
        'fitI_B_byCh','spIm','frameCount'};
    if ~all(isfield(calibration,requiredCalibration)) || ...
            ~isequal(size(calibration.spVar),imageSize) || ...
            ~isequal(size(calibration.spVarRaw),imageSize) || ...
            ~isequal(size(calibration.spShotVar),imageSize) || ...
            numel(calibration.fitI_A_byCh) ~= numel(masks) || ...
            numel(calibration.fitI_B_byCh) ~= numel(masks)
        cacheOrder = [];
        return;
    end
    for channelIdx = 1:numel(masks)
        if ~isequal(size(calibration.fitI_A_byCh{channelIdx}),imageSize) || ...
                ~isequal(size(calibration.fitI_B_byCh{channelIdx}),imageSize)
            cacheOrder = [];
            return;
        end
    end
end
isValid = true;
end

function [rawRow,corrRow,meanRow] = localCalculateScosFrame(rawFrame,divideBy, ...
        blackLevel,calibration,roi,masksCut,windowSize,actualGain)
% One shared SCOS implementation is used for fixed and every sequencer
% exposure condition. Only the selected correction structure differs.
image = double(rawFrame) ./ divideBy - blackLevel - calibration.background;
imageCut = image(roi.y,roi.x);
localVariance = stdfilt(imageCut,true(windowSize)).^2;
nChannels = numel(masksCut);
rawRow = nan(1,nChannels);
corrRow = nan(1,nChannels);
meanRow = nan(1,nChannels);

for channelIdx = 1:nChannels
    mask = masksCut{channelIdx};
    meanIntensity = mean(imageCut(mask));
    fittedIntensity = calibration.fitI_A_cut_byCh{channelIdx} .* meanIntensity + ...
        calibration.fitI_B_cut_byCh{channelIdx};
    fittedIntensitySquared = fittedIntensity.^2;
    rawRow(channelIdx) = mean(localVariance(mask) ./ fittedIntensitySquared(mask));
    correctedNumerator = localVariance - actualGain .* fittedIntensity - ...
        calibration.spVar_cut - calibration.darkVarPerWindow_cut;
    corrRow(channelIdx) = mean(correctedNumerator(mask) ./ fittedIntensitySquared(mask));
    meanRow(channelIdx) = meanIntensity;
end
end

function relativeBFI = localCalculateRelativeBFI(bfi,timeVec)
relativeBFI = nan(size(bfi));
if isempty(bfi)
    return;
end
baselineMask = timeVec <= timeVec(1) + 10;
if ~any(baselineMask)
    baselineMask(1) = true;
end
longRecording = timeVec(end) - timeVec(1) > 120;
for channelIdx = 1:size(bfi,2)
    baselineValues = bfi(baselineMask,channelIdx);
    baselineValues = baselineValues(isfinite(baselineValues));
    if isempty(baselineValues)
        continue;
    end
    if longRecording
        reference = mean(baselineValues);
    else
        reference = prctile(baselineValues,5);
    end
    if isfinite(reference) && reference ~= 0
        relativeBFI(:,channelIdx) = bfi(:,channelIdx) ./ reference;
    end
end
end

function cells = localMatrixColumnsToCells(matrix)
cells = cell(1,size(matrix,2));
for columnIdx = 1:size(matrix,2)
    cells{columnIdx} = matrix(:,columnIdx);
end
end

function selected = localSelectResultChannel(results,channelIdx)
selected = results;
for exposureIdx = 1:numel(selected.byExposure)
    selected.byExposure(exposureIdx).rawSpeckleContrast = ...
        selected.byExposure(exposureIdx).rawSpeckleContrast(:,channelIdx);
    selected.byExposure(exposureIdx).corrSpeckleContrast = ...
        selected.byExposure(exposureIdx).corrSpeckleContrast(:,channelIdx);
    selected.byExposure(exposureIdx).BFI = ...
        selected.byExposure(exposureIdx).BFI(:,channelIdx);
    selected.byExposure(exposureIdx).rBFI = ...
        selected.byExposure(exposureIdx).rBFI(:,channelIdx);
    selected.byExposure(exposureIdx).meanIntensity = ...
        selected.byExposure(exposureIdx).meanIntensity(:,channelIdx);
end
end

function localPlotExposureResults(results,recName,recSavePrefix,stdStr,isMultipleExposure)
nChannels = size(results.byExposure(1).meanIntensity,2);
for exposureIdx = 1:numel(results.byExposure)
    exposureResult = results.byExposure(exposureIdx);
    exposureLabel = localExposureFileLabel(exposureResult.exposureTimeUs);
    if isMultipleExposure
        fileSuffix = ['_exp' exposureLabel 'us'];
    else
        fileSuffix = '';
    end
    figureTitle = sprintf('%s; exposure %.12g us',recName,exposureResult.exposureTimeUs);
    nColumns = 3;

    rawFigure = figure('Name',['SCOS Raw ' figureTitle], ...
        'Units','Normalized','Position',[0.01,1-0.16-nChannels*0.15,0.9,0.05+nChannels*0.15]);
    correctedFigure = figure('Name',['SCOS Corr ' figureTitle], ...
        'Units','Normalized','Position',[0.01,1-0.16-nChannels*0.15,0.9,0.05+nChannels*0.15]);

    for channelIdx = 1:nChannels
        rawSNR = NaN; rawFFT = []; rawFrequency = [];
        corrSNR = NaN; corrFFT = []; corrFrequency = [];
        if numel(exposureResult.timeVec) >= 3 && ...
                isfinite(exposureResult.effectiveFrameRateHz) && ...
                exposureResult.effectiveFrameRateHz > 0
            try
                [rawSNR,rawFFT,rawFrequency] = CalcSNR_Pulse( ...
                    exposureResult.rawSpeckleContrast(:,channelIdx), ...
                    exposureResult.effectiveFrameRateHz,false);
                [corrSNR,corrFFT,corrFrequency] = CalcSNR_Pulse( ...
                    exposureResult.corrSpeckleContrast(:,channelIdx), ...
                    exposureResult.effectiveFrameRateHz,false);
            catch err
                warning('SCOSvsTime:ExposureFFT','Exposure %.12g us FFT skipped: %s', ...
                    exposureResult.exposureTimeUs,err.message);
            end
        end

        figure(rawFigure);
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+1);
        plot(exposureResult.timeVec,exposureResult.meanIntensity(:,channelIdx));
        title(sprintf('Ch%d - mean I',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+2);
        plot(exposureResult.timeVec,exposureResult.rawSpeckleContrast(:,channelIdx));
        title(sprintf('Ch%d - Raw',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+3);
        if isempty(rawFrequency)
            axis off; text(0.1,0.5,'FFT unavailable');
        else
            plot(rawFrequency,rawFFT); title(sprintf('FFT: SNR=%.2g',rawSNR)); xlabel('Frequency [Hz]');
        end

        figure(correctedFigure);
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+1);
        plot(exposureResult.timeVec,exposureResult.meanIntensity(:,channelIdx));
        title(sprintf('Ch%d - mean I',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+2);
        plot(exposureResult.timeVec,exposureResult.corrSpeckleContrast(:,channelIdx));
        title(sprintf('Ch%d - Corr',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+3);
        if isempty(corrFrequency)
            axis off; text(0.1,0.5,'FFT unavailable');
        else
            plot(corrFrequency,corrFFT); title(sprintf('FFT: SNR=%.2g',corrSNR)); xlabel('Frequency [Hz]');
        end

        if any(exposureResult.corrSpeckleContrast(:,channelIdx) < 0)
            warning('SCOSvsTime:NegativeContrast', ...
                'Exposure %.12g us channel %d contains negative corrected contrast.', ...
                exposureResult.exposureTimeUs,channelIdx);
        end

        if exposureResult.timeVec(end) > 120
            timeToPlot = exposureResult.timeVec / 60;
            xLabel = 'time [min]';
        else
            timeToPlot = exposureResult.timeVec;
            xLabel = 'time [sec]';
        end
        relativeFigure = figure('Name',sprintf('rBFI Ch%d: %s',channelIdx,figureTitle), ...
            'Units','Normalized','Position',[0.1,0.1,0.4,0.4]);
        subplot(2,1,1);
        plot(timeToPlot,exposureResult.rBFI(:,channelIdx));
        xlabel(xLabel); ylabel('rBFI'); title(figureTitle,'Interpreter','none'); grid on;
        subplot(2,1,2);
        plot(timeToPlot,exposureResult.meanIntensity(:,channelIdx));
        xlabel(xLabel); ylabel('<I> [DU]'); grid on;
        savefig(relativeFigure,[recSavePrefix sprintf('_rBFi_Ch%d%s.fig',channelIdx,fileSuffix)]);
    end
    savefig(rawFigure,[recSavePrefix 'Local' stdStr '_plot' fileSuffix '.fig']);
    savefig(correctedFigure,[recSavePrefix 'Local' stdStr '_plot_corrected' fileSuffix '.fig']);
end
end

function label = localExposureFileLabel(exposureTimeUs)
if ~isfinite(exposureTimeUs)
    label = 'unknown';
else
    label = regexprep(sprintf('%.12g',exposureTimeUs),'[^0-9A-Za-z]','p');
end
end
