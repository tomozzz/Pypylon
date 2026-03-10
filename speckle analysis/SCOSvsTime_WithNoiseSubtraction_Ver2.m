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

function  [ timeVec, rawSpeckleContrast , corrSpeckleContrast, meanVec , info] = ...
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

isRecordFile = false;
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
rawName = strrep( strjoin(upFolders(max(1,end-2):end),'; '), '_',' ');

if exist(recName,'file') == 7 % it's a folder
    recSavePrefix = [ recName filesep ];
else % it's a file
    recSavePrefix = [ recName(1:find(recName=='.',1,'last')-1) '_' ];
end

isNpyRecord = exist(recName,'dir') == 7 && (exist(fullfile(recName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(recName,'frames_*.npy'))));

if isNpyRecord
    [~, info, sourceFiles] = LoadNpyRecordingMeta(recName);
    nOfFrames = sourceFiles.totalFrames;
    nPreview = min(20,nOfFrames);
    previewRec = zeros([sourceFiles.imageSize nPreview]);
    for k=1:nPreview
        previewRec(:,:,k) = double(LoadNpyRecordingFrame(recName,k,sourceFiles));
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
            channels.Centers(ch,:) = circ.Center; %#ok<AGROW>
            channels.Radii(ch,1)   = circ.Radius; %#ok<AGROW>
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
            masks{1} = false(size(mask));
            masks{1}(ws2+1:end-ws2,ws2+1:end-ws2) = mask(ws2+1:end-ws2);
            totMask = M.mask > 0;
            channels.Centers = M.circ.Center;
            channels.Radii  = M.circ.Radius;
        else
            load(maskFile); %#ok<LOAD>
        end
    end
end
for k=1:numel(masks)
    masks{k}( [ 1:ws2 (end-ws2+1):end ],:) = false; %#ok<AGROW>
    masks{k}( : , [ 1:ws2 (end-ws2+1):end ]) = false; %#ok<AGROW>
end
totMask( [ 1:ws2 (end-ws2+1):end ], : ) = false;
totMask( : , [ 1:ws2 (end-ws2+1):end ]) = false;

%% Check info
upFolders = strsplit(recName,filesep);
shortRecName = strjoin(upFolders(max(1,end-2):end));

if backgroundName~=0
    if exist(backgroundName,'dir') == 7 && (exist(fullfile(backgroundName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(backgroundName,'frames_*.npy'))))
        [~,info_background] = LoadNpyRecordingMeta(backgroundName);
    else
        info_background = GetRecordInfo(backgroundName);
    end
    fields = {'expT','Gain','BL'};
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
%% Get Background and Background Noise
start_calib_time = tic;
disp('Load Background');
if ~exist(backgroundName,'file')
    error([backgroundName,' does not exist!']);
end

requiredBG_nOfFrames = 400;
if exist(backgroundName,'file') == 7 % it's a folder
    if exist(fullfile(backgroundName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(backgroundName,'frames_*.npy')))
        [~,~,bgSourceFiles] = LoadNpyRecordingMeta(backgroundName);
        nOfFramesBG = bgSourceFiles.totalFrames;
        if nOfFramesBG < requiredBG_nOfFrames
            error('Not enough frames in background file. Required : %d , Exist : %d',requiredBG_nOfFrames,nOfFramesBG);
        end
        bgRec = zeros([bgSourceFiles.imageSize requiredBG_nOfFrames]);
        for bi = 1:requiredBG_nOfFrames
            bgRec(:,:,bi) = double(LoadNpyRecordingFrame(backgroundName,bi,bgSourceFiles));
        end
        background = mean(bgRec,3);
        darkVar = std(bgRec,0,3).^2;
        if isfield(info_background,'name') && isfield(info_background.name,'BL') && ~isnan(info_background.name.BL)
            background = background - info_background.name.BL;
        end
    elseif exist( [ backgroundName '\meanIm.mat'],'file')
        bgS = load([ backgroundName '\meanIm.mat']);
        if ~isfield(bgS,'nOfFrames') 
            nOfFramesBG = GetNumOfFrames(backgroundName); 
        else
            nOfFramesBG = bgS.nOfFrames;
        end
        if   nOfFramesBG < requiredBG_nOfFrames
            error('Not enough frames in background file. Required : %d , Exist : %d',requiredBG_nOfFrames,nOfFramesBG);
        end
        if isfield(bgS,'recVar')
            background = bgS.recMean - info_background.name.BL;
            darkVar = bgS.recVar;
        else
            delete([ backgroundName '\meanIm.mat']);
            [ background , darkVar ] = ReadRecordVarAndMean( backgroundName );
            background =  background - info_background.name.BL;
        end
        clear bgS
    else
        nOfFramesBG = GetNumOfFrames(backgroundName);
        if  nOfFramesBG < requiredBG_nOfFrames
            error('Not enough frames in background file. Required : %d , Exist : %d',requiredBG_nOfFrames,nOfFramesBG);
        end
        [ background , darkVar ] = ReadRecordVarAndMean( backgroundName );
        background =  background - info_background.name.BL;
        
        if abs(mean2(background)) > 3
            my_imagesc(background); title('Background');
            warning('Suspicious level of the background %gDU !', round(mean2(background),2));
        end        
    end  
    if ~isequal(size(mean_frame),size(background))
        if exist([recName '\ROI.mat'],'file')
            ROI = load([recName '\ROI.mat']);
            if ( ROI.xLimits(end) > size(background,2) || ROI.xLimits(end)>size(background,2) )
                error(['ROI.xLimits = ' num2str(ROI.xLimits) ' ROI.yLimits = ' num2str(ROI.yLimits) ' darkIm size = [' num2str(size(background)) ']'])
            else
                background  = background(ROI.yLimits(1):ROI.yLimits(2),ROI.xLimits(1):ROI.xLimits(2));
                darkVar     = darkVar(ROI.yLimits(1):ROI.yLimits(2),ROI.xLimits(1):ROI.xLimits(2));
            end
        else
            error(['Background size is ' num2str(size(background)) ' but record size is ' num2str(size(mean_frame))]);
        end
    end
elseif endsWith(backgroundName,'.mat')
    bgS = load( backgroundName );
    fields = fieldnames(bgS);
    if ismember(fields, 'recMean')
        background = bgS.recMean - info_background.name.BL;
    elseif startsWith(fields{1}, 'Video')
        darkRec = bgS.(fields{1}); 
        bgS.recMean = mean(darkRec,3);
        background = bgS.recMean - info_background.name.BL;
        darkVar = std(double(darkRec),0,3).^2;
        bgS.recVar   = darkVar;
        save(backgroundName,'-struct','bgS')
    else
        error('wrong fields')
    end
    clear bgS
end

darkVarPerWindow = imboxfilt(darkVar,windowSize) ;

if ~isequal(size(background),size(im1))
    error('The background should be the same picture size as the record. Record size is [%d,%d], but background size is [%d,%d]',size(im1,1), size(im1,2), size(background,1), size(background,1));
end
%% Get G[DU/e]
nOfBits = info.nBits;
actualGain = GetActualGain(info);
 
%% Calc spatialNoise 
if ~isfield(info.name , 'BL' )
    BlackLevel = 0;
else
    BlackLevel = info.name.BL;
end

smoothCoeffFile = [recName  '\smoothingCoefficients.mat'];
if ~exist(smoothCoeffFile,'file') 
    % TBD check if it was calculated with the same mask & window size
    disp('Calc Spatial Noise and Smoothing Coefficients');
    numFramesForSPNoise = 600;
    if nOfFrames > 1000 ;  numFramesForSPNoise=1000; end
    spRec = zeros([sourceFiles.imageSize numFramesForSPNoise]);
    for si = 1:numFramesForSPNoise
        spRec(:,:,si) = double(LoadNpyRecordingFrame(recName,si,sourceFiles));
    end
    spRec = spRec - BlackLevel;
    spIm = mean(spRec,3) - background;
    fig_spIm = my_imagesc(spIm); title(['Image average ' num2str(numFramesForSPNoise) ' frames'] );
    savefig(fig_spIm, [recName '\spIm.fig']);
    spVar = stdfilt( spIm ,true(windowSize)).^2;
    [fitI_A,fitI_B] = FitMeanIm(spRec,totMask,windowSize);
    clear spRec
    save(smoothCoeffFile,'spVar','fitI_A','fitI_B','spIm','totMask');
else
    % TBD check if it was calculated with the same mask & window size
    disp('Load Spatial Noise and Smoothing Coefficients');
    load(smoothCoeffFile);
end

disp('Calibration Time')
toc(start_calib_time)

%% Decrease Image Size
[y,x] = find(totMask) ;
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
   
fitI_A_cut =  fitI_A(roi.y  , roi.x);
fitI_B_cut =  fitI_B(roi.y  , roi.x);
% bpMap_cut = bpMap(roi.y  , roi.x);
%% Calc Specle Contrast
disp(['Calculating SCOS on "' recName '" ... ']);
disp(['Mono' num2str(nOfBits)]);
nOfChannels = numel(masks);
frameNames = cell(nOfFrames,1);
% init loop vars
[ rawSpeckleContrast , corrSpeckleContrast , meanVec] =InitNaN([nOfFrames 1],nOfChannels);
timeVecFile = nan([nOfFrames 1]);

im1 = double(im1);

devide_by = 1;
if nOfBits == 12  && all(mod(im1(:),2^4) == 0)
    devide_by = 2^4;
elseif nOfBits == 10  && all(mod(im1(:),2^6) == 0)
    devide_by = 2^6;
end


start_scos = tic;
               
for i=1:nOfFrames
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

    [imFrame,tFrame,frameName] = LoadNpyRecordingFrame(recName,i,sourceFiles);
    im_raw = double(imFrame) / devide_by;
    im_raw = im_raw - BlackLevel;
    frameNames{i} = frameName;
    if ~isnan(tFrame)
        timeVecFile(i) = tFrame;
    else
        timeVecFile(i) = i/frameRate;
    end

    im = im_raw - background;
    im_cut = im(roi.y,roi.x);
    stdIm = stdfilt(im_cut,true(windowSize));

    for ch = 1:nOfChannels
        meanFrame = mean(im_cut(masks_cut{ch}));
        fittedI = fitI_A_cut*meanFrame + fitI_B_cut ;
        fittedISquare = fittedI.^2;

        rawSpeckleContrast{ch}(i) = mean((stdIm(masks_cut{ch}).^2 ./ fittedISquare(masks_cut{ch})));
        corrSpeckleContrast{ch}(i) = mean( ( stdIm(masks_cut{ch}).^2 - actualGain.*fittedI(masks_cut{ch})  - spVar(masks_cut{ch}) - 1/12 - darkVarPerWindow(masks_cut{ch}))./fittedISquare(masks_cut{ch}) );
        meanVec{ch}(i) = meanFrame;
        if i==1
            fprintf('<I>=%.3gDU , K_raw = %.5g , Ks=%.5g , Kr=%.5g, Ksp=%.5g, Kq=%.5g, Kf=%.5g\n',meanFrame,rawSpeckleContrast{ch}(i), ...
               mean(actualGain.*fittedI(masks_cut{ch})./fittedISquare(masks_cut{ch})),mean(darkVar(masks_cut{ch})./fittedISquare(masks_cut{ch})),...
               mean(spVar(masks_cut{ch})./fittedISquare(masks_cut{ch})),mean(1./(12*fittedISquare(masks_cut{ch}))),corrSpeckleContrast{ch}(i));
        end
    end
end
fprintf('\n');
            end
        end

        im_raw = double(batchRec(:,:,j)) / devide_by;
        im_raw = im_raw - BlackLevel;
        frameNames{i} = batchSourceFiles.frameNames{j};
        if numel(batchTimeVec) >= j && ~isnan(batchTimeVec(j))
            timeVecFile(i) = batchTimeVec(j);
        else
            timeVecFile(i) = i/frameRate;
        end

        im = im_raw - background;
        im_cut = im(roi.y,roi.x);
        stdIm = stdfilt(im_cut,true(windowSize));

        for ch = 1:nOfChannels
            meanFrame = mean(im_cut(masks_cut{ch}));
            fittedI = fitI_A_cut*meanFrame + fitI_B_cut ;
            fittedISquare = fittedI.^2;

            rawSpeckleContrast{ch}(i) = mean((stdIm(masks_cut{ch}).^2 ./ fittedISquare(masks_cut{ch})));
            corrSpeckleContrast{ch}(i) = mean( ( stdIm(masks_cut{ch}).^2 - actualGain.*fittedI(masks_cut{ch})  - spVar(masks_cut{ch}) - 1/12 - darkVarPerWindow(masks_cut{ch}))./fittedISquare(masks_cut{ch}) );
            meanVec{ch}(i) = meanFrame;
            if i==1
                fprintf('<I>=%.3gDU , K_raw = %.5g , Ks=%.5g , Kr=%.5g, Ksp=%.5g, Kq=%.5g, Kf=%.5g\n',meanFrame,rawSpeckleContrast{ch}(i), ...
                   mean(actualGain.*fittedI(masks_cut{ch})./fittedISquare(masks_cut{ch})),mean(darkVar(masks_cut{ch})./fittedISquare(masks_cut{ch})),...
                   mean(spVar(masks_cut{ch})./fittedISquare(masks_cut{ch})),mean(1./(12*fittedISquare(masks_cut{ch}))),corrSpeckleContrast{ch}(i));
            end
        end
    end
    clear batchRec batchTimeVec batchSourceFiles
end
fprintf('\n');
%% Create Time vector
timeVec = (0:(nOfFrames-1))'*(1/frameRate) ;   % FR = FrameRate
p2p_time = timeVec<timePeriodForP2P;
% Calculate BFI for all channels
BFi = cell(1,nOfChannels);
BFI_matrix = zeros(nOfFrames,nOfChannels);
meanI_matrix = zeros(nOfFrames,nOfChannels);
for ch = 1:nOfChannels
    BFi{ch} = 1./corrSpeckleContrast{ch};
    BFI_matrix(:,ch) = BFi{ch};
    meanI_matrix(:,ch) = meanVec{ch};
end
%% Save
stdStr = sprintf('Std%dx%d',windowSize,windowSize);
if exist([recSavePrefix 'Local' stdStr '.mat'],'file'); delete([recSavePrefix 'Local' stdStr '.mat']); end % just for it to have the right date
startDateTime = sourceFiles.startDateTime;
if isempty(startDateTime)
    startDateTime = datestr(now);
end
save([recSavePrefix 'Local' stdStr '_corr.mat'],'startDateTime','timeVec', 'corrSpeckleContrast' , 'rawSpeckleContrast', 'meanVec', 'info','nOfChannels', 'recName','windowSize','timeVecFile','frameNames');
BFI_output = struct('timeVec',timeVec,'BFI',BFI_matrix,'meanI',meanI_matrix,'channels',channels);
save([recSavePrefix 'BFI_output.mat'],'-struct','BFI_output');
for ch = 1:nOfChannels
    singleBFI.timeVec = timeVec;
    singleBFI.BFI = BFI_matrix(:,ch);
    singleBFI.meanI = meanI_matrix(:,ch);
    save([recSavePrefix sprintf('BFI_Ch%d.mat',ch)],'-struct','singleBFI');
end

%% Plot
infoFields = fieldnames(info.name);
if ~isfield(info.name,'Gain')
    info.name.Gain = '';
end
firtsParamValue = info.name.(infoFields{1});
if ~ischar(firtsParamValue)
    firtsParamValue = num2str(firtsParamValue);
end
if isfield(info.name,'SDS')
    titleStr =  [ infoFields{1} firtsParamValue ' SDS=' num2str(info.name.SDS)  '; exp=' num2str(info.name.expT)  'ms; Gain='  num2str(info.name.Gain) 'dB' ];
else
    titleStr =  [ infoFields{1} firtsParamValue '; exp=' num2str(info.name.expT)  'ms; Gain='  num2str(info.name.Gain) 'dB' ];
end

Nx = 3;
if plotFlag
    fig_raw = figure('name',['SCOS Raw ' recName],'Units','Normalized','Position',[0.01,1-0.16-nOfChannels*0.15,0.9,0.05+nOfChannels*0.15]);
    for ch = 1:nOfChannels
        try
            [raw_SNR,raw_FFT,raw_freq,raw_pulseFreq,raw_pulseBPM] = CalcSNR_Pulse(rawSpeckleContrast{ch},frameRate,false);
        catch err
            warning(err.message);
        end
        subplot(nOfChannels,Nx,Nx*(ch-1)+1);
            plot(timeVec,meanVec{ch});
            title(sprintf('Ch%d - mean I',ch));
            xlim([0 timeVec(end)]); xlabel('Time [s]');
        subplot(nOfChannels,Nx,Nx*(ch-1)+2);
            plot(timeVec,rawSpeckleContrast{ch});
            title(sprintf('Ch%d - Raw',ch)); xlabel('Time [s]');
        subplot(nOfChannels,Nx,Nx*(ch-1)+3);
            plot(raw_freq,raw_FFT); title(sprintf('FFT: SNR=%.2g',raw_SNR)); xlabel('Frequency [Hz]');
    end
    savefig(fig_raw,[recSavePrefix 'Local' stdStr '_plot.fig']);

    fig_corr = figure('name',['SCOS Corr ' recName],'Units','Normalized','Position',[0.01,1-0.16-nOfChannels*0.15,0.9,0.05+nOfChannels*0.15]);
    for ch = 1:nOfChannels
        try
            [corr_SNR,corr_FFT,corr_freq,corr_pulseFreq,corr_pulseBPM] = CalcSNR_Pulse(corrSpeckleContrast{ch},frameRate,false);
        catch err
            warning(err.message);
        end
        subplot(nOfChannels,Nx,Nx*(ch-1)+1);
            plot(timeVec,meanVec{ch});
            title(sprintf('Ch%d - mean I',ch));
            xlim([0 timeVec(end)]); xlabel('Time [s]');
        subplot(nOfChannels,Nx,Nx*(ch-1)+2);
            plot(timeVec,corrSpeckleContrast{ch});
            title(sprintf('Ch%d - Corr',ch)); xlabel('Time [s]');
        subplot(nOfChannels,Nx,Nx*(ch-1)+3);
            plot(corr_freq,corr_FFT); title(sprintf('FFT: SNR=%.2g',corr_SNR)); xlabel('Frequency [Hz]');
    end
    savefig(fig_corr,[recSavePrefix 'Local' stdStr '_plot_corrected.fig']);
end

%% Plot rBFI
for ch = 1:nOfChannels
    if any(corrSpeckleContrast{ch} < 0)
        warning('Error: There are negative values in the contrast !!!');
    end
end

if plotFlag
    for ch = 1:nOfChannels
        BFi_ch = BFi{ch};
        if timeVec(end) > 120
            timeToPlot = timeVec / 60; xLabelStr = 'time [min]';
            rBFi = BFi_ch/mean(BFi_ch(1:round(10*frameRate)));
        else
            timeToPlot = timeVec; xLabelStr = 'time [sec]';
            rBFi = BFi_ch/prctile(BFi_ch(1:round(10*frameRate)),5);
        end
        fig_r = figure('Name',sprintf('rBFi Ch%d: %s',ch,recName),'Units','Normalized','Position',[0.1,0.1,0.4,0.4]);
        subplot(2,1,1);
            plot(timeToPlot,rBFi); xlabel(xLabelStr); ylabel('rBFi'); title(titleStr); grid on;
        subplot(2,1,2);
            plot(timeToPlot,meanVec{ch}); xlabel(xLabelStr); ylabel('<I> [DU]'); grid on;
        savefig(fig_r,[recSavePrefix sprintf('_rBFi_Ch%d.fig',ch)]);
    end
end

%%
toc(start_scos)
end

