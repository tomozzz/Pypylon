%% Set Parameters - Must run this section before any other section in the file
windowSize = 9; % for spatial local noise calculation
rootFolder = fileparts(fileparts(mfilename('fullpath')));
if isempty(rootFolder); rootFolder = '.\'; end
noiseFolder = [rootFolder '\Records\NoiseAndBackground'];
if ~exist(noiseFolder,'dir'); mkdir(noiseFolder) ; end
detectorName = 'Basler_1440GS_Tomoya_24828238';
videoFormat = 'Mono12'; 

analysisFolder = [noiseFolder filesep detectorName filesep videoFormat];
if ~exist(analysisFolder,'dir'); mkdir(analysisFolder); end
set(groot,'defaultAxesFontSize',12)
mFolder = fileparts(mfilename('fullpath'));
addpath(['.\baseFunc']);
bitDepth = sscanf(videoFormat,'%*[a-zA-Z]%d');

recordFlag = 0; % if off it will try to load the data from the predefined filename
rewriteFlag = 0; % if recordFlag == 0, and recordings already exist, rewrite it.

setupParams = struct();
setupParams.CameraModel = 'Basler_acA1440-220um';
setupParams.CameraSN = '24828238';
setupParams.addToFilename = false;

% Flags
rerecord_RN = 1; % rerecord read noise if it's already been recorded - closed camera
recalc_RN = 1;
rerecord_DCN = 1; % rerecord darc current noise if it's already been recorded - closed camera
recalc_DCN = 1;
rerecord_SN1 = 0; % rerecord darc current noise if it's already been recorded - white paper/illumination device
recalc_SN1 = 0;
% Note : each section has two/three parts : Record , Calc and Plot
%% 0. How many frames to Average?
% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Num Of Frames - Record and Calc
% use recording with uniform signal approximately at the middle of the dynamic range, with more than 300 frames
numOfFramesFolder = [ noiseFolder filesep 'NumOfFrames\nOfFrames'];
if ~exist(numOfFramesFolder,'file'); mkdir(numOfFramesFolder); end
matFileNumOfFrames = [ numOfFramesFolder filesep 'data.mat' ];
if recordFlag || ~exist(numOfFramesFolder,'dir') || ~exist(matFileNumOfFrames,'file')
    max_nOfFrames = 200;
   
    camParams.ExposureTime = 1000; % 1ms
    camParams.Gain   = 0;
    forceWrite = 1;
    setupParams.Background = 'WhitePaper'; setupParams.addToFilename = 0;
    camParams.videoFormat = videoFormat;  camParams.addToFilename.videoFormat = false;
    
    % Record
    [ rec, numOfFramesFile, info ] = RecordFromCamera(max_nOfFrames,camParams,setupParams,numOfFramesFolder,'.tiff','WhitePaper','',forceWrite);
    
    %     recFile = [numOfFramesFolder '/WhitePaperTint5ms_Gain20dB_FR100Hz_BL30DU_300frames'];
    %     rec = ReadRecord(recFile);

    totRecSize = size(rec,3);
    nOfFramesArr = [ 3:3:20 , 30:10:100 120:30:totRecSize ];

       
    % Calc
    nFrames = struct();
    [nFrames.locSpatNoise, nFrames.globSpatNoise, nFrames.tempNoise ] = InitNaN(size(nOfFramesArr));
    for i=1:numel(nOfFramesArr)
        fprintf('num of frames = %d\n',nOfFramesArr(i));
        [nFrames.locSpatNoise(i), nFrames.globSpatNoise(i), nFrames.tempNoise(i) , ~ ,nFrames.meanImPerFrame] = CalcNoise(rec(:,:,1:nOfFramesArr(i)),windowSize);
    end
    % Save
    save(matFileNumOfFrames,'nFrames','numOfFramesFile');
else
    load(matFileNumOfFrames);
end
%% Num Of Frames - Plot
fig = figure('name','How many frames to Average?'); 
subplot(2,1,1)
plot(nOfFramesArr,nFrames.locSpatNoise,'.-'); hold on
plot(nOfFramesArr,nFrames.globSpatNoise,'.-');
plot(nOfFramesArr,nFrames.tempNoise,'.-g'); 
legend('local Spatial', 'globalSpatial', 'temporal');
grid on
xlabel('number of frames');
ylabel('Noise [DU]')
[~,recName] = fileparts(numOfFramesFile);
title([ recName ' ; Mean = ' num2str(mean2(rec(:,:,1)),3) 'DU' ],'interpreter','none');
grid minor

subplot(2,1,2);
plot(nFrames.meanImPerFrame); xlabel('frame number'); ylabel('mean(I) [DU')
grid on

savefig(fig,[analysisFolder '\numOfFrames.fig']);

%% 1. Read Noise (minimum exposure time, with Cover)
%% Read Noise vs BlackLevel - Record
readNoiseBLFolder = [ analysisFolder filesep 'ReadNoise\vsBlackLevel'];

if rerecord_RN
    setupParams.Cover = 'On';
    
    if bitDepth == 8
        BL.gainArr = [0:15:30,36];
        BL.blackLevelArr = [0:6,10:10:30];
    else
        BL.blackLevelArr = [0:5:35 40:10:60 100 200 300];
        BL.gainArr = [0 15 20 24];
    end
    prefix = 'Cover';
    suffix = '';
    nOfFrames = 90;
    if bitDepth == 8
        recFormat = '.avi';
    else
        recFormat = '.tiff';
    end
    camParams = struct();
    camParams.AcquisitionFrameRate = 20; 
    camParams.ExposureTime = 21; % the minimum possible
    camParams.videoFormat = videoFormat;
    camParams.addToFilename.videoFormat = false;

    if ~exist(readNoiseBLFolder,'file'); mkdir(readNoiseBLFolder); end
    if numel(dir(readNoiseBLFolder)) > 2 % in case of empty folder the result of dir() is {'.','..'} 
        answer = input(['"' readNoiseBLFolder '" is not empty, are you sure you want to rewrite it? (Y/N) '],'s'); 
        if ~strcmpi(answer,'Y')
           disp('Aborting...');
           return; 
        end
    end
    % record 
    vid = videoinput("gentl", 1, videoFormat);% vid =[];
    for gain = BL.gainArr
        for bl = BL.blackLevelArr
            camParams.BlackLevel = bl;
            camParams.Gain = gain;
            RecordFromCamera(nOfFrames, camParams, setupParams , readNoiseBLFolder , recFormat, prefix, suffix, 1 , 0 , vid);
        end
    end
    delete(vid);
    clear gain bl camParams
end
%% Read Noise vs BlackLevel - Calc
readNoiseVsBL_matfile = [readNoiseBLFolder filesep 'readNoiseVsBL.mat'];
if ~exist(readNoiseVsBL_matfile,'file') || recalc_RN 
    [ records , BL.gainArr ] = ChooseRecords( readNoiseBLFolder  ,['Cover*Gain*'] , 'Gain' );
    BL.gainArr = unique(BL.gainArr);
    [ BL.records, BL.blackLevelArr ] = SortRecords(records,'BL');
    BL.blackLevelArr = unique(BL.blackLevelArr);

    disp('Calculating Read Noise vs Black Level...')
    [ BL.locSpatNoise ,BL.globSpatNoise, BL.tempNoise , BL.meanI]  = InitNaN( [numel(BL.gainArr) numel(BL.blackLevelArr)] );
    for gain_i = 1:numel(BL.gainArr)
        for bl_i = 1:numel(BL.blackLevelArr)
            filter = sprintf('Cover*BL%gDU*Gain%gdB*',BL.blackLevelArr(bl_i),BL.gainArr(gain_i));
            recName = ChooseRecords( readNoiseBLFolder  ,filter);
            if numel(recName) < 1
                error('%s record was not found in %s',filter,readNoiseBLFolder);
            elseif numel(recName) > 1
                error('More that one file with the format %s was found in %s',filter,readNoiseBLFolder); 
            end
            disp(recName{1})
            [BL.locSpatNoise(gain_i,bl_i), BL.globSpatNoise(gain_i,bl_i), BL.tempNoise(gain_i,bl_i), BL.meanI(gain_i,bl_i)] = CalcNoise(recName{1},windowSize,[],0);
        end
    end

    save(readNoiseVsBL_matfile,'-struct','BL')
else
    BL = load(readNoiseVsBL_matfile);
end   
disp('Finish calculating read noise vs black level');
%% Read Noise vs BlackLevel - Plot
blFig = figure('name','black level influence on read noise','Units','Normalized','Position',[0.1 0.1 0.9 0.6]);
subplot(1,2,1);
for gain_i = 1:numel(BL.gainArr)
    plot(BL.blackLevelArr,BL.locSpatNoise(gain_i,:),'*-'); hold on;
end
title('Read Noise - Local Spatial')
ylabel('Noise [DU]');
xlabel('Black Level [DU]')
legend(strcat({'Gain '} , num2cellstr(BL.gainArr), 'dB'),'location','best');

subplot(1,2,2);
for gain_i = 1:numel(BL.gainArr)
    plot(BL.blackLevelArr,BL.tempNoise(gain_i,:),'*-'); hold on
end
title('Read Noise - Temporal')
legend(strcat({'Gain '} , num2cellstr(BL.gainArr), 'dB'),'location','best');

for i=1:2
    subplot(1,2,i);
    ylabel('Noise [DU]');
    xlabel('Black Level [DU]')
    set(gca,'YLim', [-0.1  max([BL.locSpatNoise(:) ; BL.tempNoise(:)]) + 0.1 ]);
    grid on
end

savefig(blFig, [analysisFolder '\ReadNoise vs BlackLevel.fig'])

%% Read Noise vs Gain - Record
readNoiseVsGainFolder = [ analysisFolder filesep 'ReadNoise\vsGain'];
if bitDepth==8
    RN.gainArr = [ 0:5:25 27 30 33 36];
else
    RN.gainArr = [ 0:5:20 24]; % mono12 has only gain up to 24
end
RN.blackLevel = 30;
prefix = 'Cover';
suffix = '';
nOfFrames = 90;
recFormat = '.tiff';
camParams = struct();
camParams.AcquisitionFrameRate = 100; % the minimum possible
camParams.ExposureTime = 21; % the minimum possible
camParams.videoFormat = videoFormat;
camParams.addToFilename.videoFormat = false;
camParams.BlackLevel = RN.blackLevel;

if ~exist(readNoiseVsGainFolder,'file'); mkdir(readNoiseVsGainFolder); end
if numel(dir(readNoiseVsGainFolder)) > 2 % in case of empty folder the result of dir() is {'.','..'} 
    answer = input(['"' readNoiseVsGainFolder '" is not empty, are you sure you want to rewrite it? (Y/N) '],'s'); 
    if ~strcmpi(answer,'Y')
       disp('Aborting...');
       return; 
    end
end
% record 
vid = videoinput("gentl", 1, videoFormat);% vid =[];
for gain = RN.gainArr
    camParams.Gain = gain;
    RecordFromCamera(nOfFrames, camParams, setupParams , readNoiseVsGainFolder  , recFormat, prefix, suffix, 1 , 0 , vid);
end
delete(vid);
clear gain bl camParams
disp('Finished Recording Read Noise vs Gain');
%% Read Noise vs Gain - Calc
    
readNoiseVsGain_matfile = [readNoiseVsGainFolder filesep 'readNoiseVsGain.mat'];
if ~exist(readNoiseVsGain_matfile,'file') || recalc_RN 
    % if you want to choose specific black level uncomment the next two line , and comment the followint Choose Records block 
    blackLevel=30;
    [ records , RN.gainArr ] = ChooseRecords( readNoiseVsGainFolder  , ['Cover*BL' num2str(blackLevel) 'DU*Gain*'], 'Gain'  );

%     [ records , gainArr ] = ChooseRecords( readNoiseVsGainFolder  , 'Cover*Gain*', 'Gain'  );
    [~,blackLevelArr] = SortRecords(records,'BL'); 
    RN.blackLevel=blackLevelArr(1);
    if numel(unique(blackLevelArr))~=1
        error('Read Noise vs Gain: There should be only one black level.')
    end

    disp('Calculating Read Noise vs Gain...')
    [ RN.locSpatNoise ,RN.globSpatNoise, RN.tempNoise , RN.meanI]  = InitNaN( [numel(RN.gainArr) numel(RN.blackLevel)] );
    for gain_i = 1:numel(RN.gainArr)
         disp(records{gain_i})
        [RN.locSpatNoise(gain_i), RN.globSpatNoise(gain_i), RN.tempNoise(gain_i), RN.meanI(gain_i)] = CalcNoise(records{gain_i},windowSize,[],0);
    end

    RN.totNoise = sqrt(RN.locSpatNoise.^2 + RN.tempNoise.^2 );

    save(readNoiseVsGain_matfile,'-struct','RN')
else
    RN = load(readNoiseVsGain_matfile);
end
disp('Finished Read Noise vs Gain Calculation');
%% Read Noise vs Gain - Plot
% 1. left plot Read Noise in DU, right plot Read Noise in [e]
rnFig = figure('name', 'ReadNoise vs Gain' ,'Units','Normalized','Position',[0.3 0.2 0.63 0.4]);

subplot(1,2,1)
plot(10.^(RN.gainArr/20) ,RN.tempNoise,'*-'); hold on
plot(10.^(RN.gainArr/20) ,RN.locSpatNoise,'*-');
plot(10.^(RN.gainArr/20) ,RN.totNoise ,'*-');
ylabel('Noise [DU]');
xlabel('Gain [rel]')
title([' Read Noise [DU] vs Gain , BlackLevel=' , num2str(RN.blackLevel)])
legend({'temporal', 'local spatial', 'total'},'location','northwest');
grid on;
grid  minor 


% 1C plot Read Noise in [e]
wellCapacity = 10.5e3;
nBits = 8;
RN.actualGainArr = reshape( ConvertGain(RN.gainArr,nBits,wellCapacity), [numel(RN.gainArr) 1] );

subplot(1,2,2);
plot(10.^(RN.gainArr/20),RN.tempNoise./RN.actualGainArr,'*-'); hold on
plot(10.^(RN.gainArr/20),RN.locSpatNoise./RN.actualGainArr,'*-');
plot(10.^(RN.gainArr/20),RN.totNoise./RN.actualGainArr ,'*-');
ylabel('Noise [e]');
xlabel('Gain [rel]');
grid on ;
grid  minor 
title([' Read Noise [e] vs Gain , BlackLevel=' , num2str(RN.blackLevel)])
legend({'temporal', 'local spatial', 'total'},'location','northeast');

savefig(rnFig, [analysisFolder '\ReadNoise vs Gain BL' num2str(RN.blackLevel) '.fig'])

%% 2. Dark Current Noise (slope of different exposure times, with Cover) , different Gains
%% Dark Current -  Record 
darkCurrentFolder = [ analysisFolder filesep 'DarkCurrent\vsTintvsGain'];
nOfFrames = 100;
if rerecord_DCN
    setupParams.Cover = 'On'; %#ok<UNRCH>
    if ~exist(darkCurrentFolder,'dir'); mkdir(darkCurrentFolder); end
    prefix = 'Cover'; suffix ='';
    DCN.expTArr = [0.021 , 0.2 , 2 , 10 , 30 , 50 , 75, 100 , 125 , 150 , 200 ]*1e3;
    if bitDepth==8
        DCN.gainArr =  [0:5:30,36];
        recFormat = '.avi';
    else
        DCN.gainArr = [ 0:5:20 24]; % mono12 has only gain up to 24
        recFormat = '.tiff';
    end

    overwriteFlag = true;
    plotFlag = false;
    camParams = struct();
    camParams.AcquisitionFrameRate = 100; 
    camParams.BlackLevel = 30;

    vid = videoinput("gentl", 1, videoFormat);
    files = cell(numel(DCN.gainArr), numel(DCN.expTArr));
    for gain = DCN.gainArr
        for expT = DCN.expTArr
            camParams.Gain = gain;
            camParams.ExposureTime = expT;
            RecordFromCamera(nOfFrames, camParams, setupParams , darkCurrentFolder  , recFormat, prefix, suffix, overwriteFlag , plotFlag , vid);
        end
    end
    delete(vid);
    clear gain expT camParams
end
disp('Finished Recording Dark Current')

%% Dark Current -  Calc
darkCurrent_matfile = [darkCurrentFolder filesep 'darkCurrentNoiseVsGainVsExpt.mat'];
if exist(darkCurrent_matfile,'file') || recalc_DCN
    recFormat = '*Cover*Gain*expT*.avi';
    [ recordsTemp , gainArr_tmp] = ChooseRecords(darkCurrentFolder , recFormat , 'Gain');
    DCN.gainArr = unique(gainArr_tmp);
    [ ~, expTValues_tmp ] = SortRecords(recordsTemp, 'expT');
    DCN.expTArr = unique(expTValues_tmp);
    nOfFrames = 100;

    [ expTVec, locSpatNoise , globSpatNoise, tempNoise , meanI]  = InitNaN([numel(gainArr), numel(expTValues)]);

    for gain_i = 1:numel(DCN.gainArr)
        [ records , expTVec_tmp] = ChooseRecords( darkCurrentFolder ,['*Cover*Gain' num2str(DCN.gainArr(gain_i)) 'dB*expT*.avi'] , 'expT' );
        if ~isequal(expTVec_tmp,DCN.expTArr) 
            error('Dark current noise: there must be the same expT values for all gains');
        end
        for expt_i = 1:numel(records)
            disp(records{expt_i})
%             tic
            rec  = ReadRecord(records{expt_i},nOfFrames);
%             toc
            [DCN.locSpatNoise(gain_i,expt_i), DCN.globSpatNoise(gain_i,expt_i), DCN.tempNoise(gain_i,expt_i), DCN.meanI(gain_i,expt_i) ] = ...
                CalcNoise(rec,windowSize,[],0);
        end
    end
    save(darkCurrent_matfile,'-struct','DCN')

else
   DCN = load(darkCurrent_matfile);
end

%% %% Dark Current -  Plot 
plotVariance = 0; % weather to plot Noise(std) or Var (std^2)
gain = 20; % plot of single gain
gain_i = find(DCN.gainArr==gain,1);

if plotVariance
   yStr = 'Noise^2 [DU^2]';
else
   yStr = 'Noise [DU]'; 
end

figDCN1 = figure('name','Dark Noise - Single Gain'); 
% subplot(2,1,1); 

% plot(tintVec(gain_i,:),globSpatNoise(gain_i,:).^2,'*-');
hold on; 
if plotVariance
    plot(DCN.expTArr,DCN.tempNoise(gain_i,:).^2,'*-');
    plot(DCN.expTArr,DCN.locSpatNoise(gain_i,:).^2,'*-'); %#ok<UNRCH>
else
    plot(DCN.expTArr,DCN.tempNoise(gain_i,:),'*-');
    plot(DCN.expTArr,DCN.locSpatNoise(gain_i,:),'*-');
end
legend({'Temporal','local Spatial'},'location','best');
title(['White Paper, Gain' num2str(gain) ' : Noise vs Integration Time ']);
ylabel(yStr)
xlabel('expT [ms]');
grid on 

% subplot(2,1,2); 
% plot(tintVec,meanI(gain_i,:) - offsetVec(gain_i,:),'o-');
% ylabel('mean(I) - Offset [DU]')
% xlabel(['Tint [' tintUnits ']']);

savefig(figDCN1,[analysisFolder '.\Dark Noise Single Gain.fig']) 

%% 2B.  Dark Current - Plot noises for different gains
figDCN2 = figure('name','Dark Current - for Different Gains');
subplot(1,2,2);
for gain_i = 1:numel(DCN.gainArr)
    if plotVariance
        plot(DCN.expTArr/1e3,DCN.tempNoise(gain_i,:).^2,'*-'); %#ok<UNRCH>
    else
        plot(DCN.expTArr/1e3,DCN.tempNoise(gain_i,:),'*-');
    end
    hold on;
end
ylabel(yStr)
xlabel('Exposure Time [ms]');
set(gca,'YLim',[0 4])
legend(strcat({'Gain '} , num2cellstr(DCN.gainArr), 'dB'),'location','northwest')
title('Temporal Noise');
grid on 


subplot(1,2,1);
for gain_i = 1:numel(DCN.gainArr)
    if plotVariance            
        plot(DCN.expTArr/1e3,DCN.locSpatNoise(gain_i,:).^2,'*-'); %#ok<UNRCH>
    else
        plot(DCN.expTArr/1e3,DCN.locSpatNoise(gain_i,:),'*-');
    end
    hold on;
end
ylabel(yStr)
xlabel(['Exposure Time [ms]']);
legend(strcat({'Gain '} , num2cellstr(DCN.gainArr), 'dB'),'location','northwest')
title('Local Spatial Noise')
set(gca,'YLim',[0 4])
grid on 
savefig(figDCN2,[analysisFolder '.\Dark Noise All Gain.fig']) 

% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

%% 3. Shot noise (White paper, different illumination levels, different gains) 
% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% 3A. Shot Noise vs Gain Vs expT
shotNoise1Folder = [ analysisFolder filesep 'ShotNoise\vsExpTvsGain'];
shotNoise1_matfile = [shotNoise1Folder filesep 'shotNoiseVsGainVsExpt.mat'];

nOfFrames = 100;
if rerecord_SN1
    setupParams.Cover = 'Off'; %#ok<UNRCH>
    if ~exist(shotNoise1Folder,'dir'); mkdir(shotNoise1Folder); end
    prefix = 'WhitePaper'; suffix ='';
    recFormat = '.avi';
    SN1.expTArr = [0.021 0.2 , 2 , 10 , 30 , 50 , 75, 100 , 125 , 150 , 200 ]*1e3;
    SN1.gainArr = [0:5:30,36];
    overwriteFlag = true;
    plotFlag = false;
    camParams = struct();
    camParams.AcquisitionFrameRate = 20; 
    camParams.BlackLevel = 0;

    vid = videoinput("gentl", 1, videoFormat);
    files = cell(numel(SN1.gainArr), numel(SN1.expTArr));
    for gain = SN1.gainArr
        break_from_this_gain = false;
        for expT = SN1.expTArr
            if break_from_this_gain; continue; end
            camParams.Gain = gain;
            camParams.ExposureTime = expT;
            im = RecordFromCamera(1, camParams);
            hst = histcounts(im,256);
            if hst(end) > numel(im)*0.001 % image saturated
                break_from_this_gain = true; % continue for all the other expT
                continue;
            end
            rec = RecordFromCamera(nOfFrames, camParams, setupParams , shotNoise1Folder  , recFormat, prefix, suffix, overwriteFlag , plotFlag , vid);  
            [SN1.locSpatNoise(gain_i,expt_i), SN1.globSpatNoise(gain_i,expt_i), SN1.tempNoise(gain_i,expt_i), SN1.meanI(gain_i,expt_i) ] = ...
                CalcNoise(rec,windowSize,[],0);
            SN1.gainMat(gain_i,expt_i) = gain;
            SN1.expTMat(gain_i,expt_i) = expT;
        end
    end
    SN1.meanI(gain_i,expt_i) = SN1.meanI(gain_i,expt_i) - camParams.BlackLevel;
    delete(vid);
    clear gain expT camParams
    
    save(shotNoise1_matfile,'-struct','SN1')
end
%% Shot Noise - Plot VS expT vs Gain : Temporal and Spatial
figSN1 = figure('name','Shot Noise - Temporal and Spatial');
subplot(1,2,2);
for gain_i = 1:numel(SN1.gainArr)
    plot(SN1.expTArr/1e3,SN1.tempNoise(gain_i,:),'*-');
    hold on;
end
ylabel(yStr)
xlabel('Exposure Time [ms]');
set(gca,'YLim',[0 4])
legend(strcat({'Gain '} , num2cellstr(SN1.gainArr), 'dB'),'location','northwest')
title('Temporal Noise');
grid on 


subplot(1,2,1);
for gain_i = 1:numel(SN1.gainArr)    
    plot(SN1.expTArr/1e3,SN1.locSpatNoise(gain_i,:),'*-');
    hold on;
end
ylabel(yStr)
xlabel('Exposure Time [ms]');
legend(strcat({'Gain '} , num2cellstr(SN1.gainArr), 'dB'),'location','northwest')
title('Local Spatial Noise')
set(gca,'YLim',[0 4])
grid on 
savefig(figSN1,[analysisFolder '.\ShotNoise_TemporalAndSpatial.fig']) 

%% Shot Noise - Temp Noise Vs Gain
bitDepth = str2double(videoFormat(5:end)); % 8 or 12
satCapacity = 10.5e3;
figure;
plot( ConvertGain(SN1.gainMat(:),bitDepth,satCapacity) , SN1.tempNoise(:)^2./SN1.meanI(:) ) ;
xlabel(' G [DU/e-] ');
ylabel(' Var(I)/<I> ');

% Plot for single gain:
figure;
SN1.gainMat(;
plot(SN1.meanI(:) , SN1.tempNoise(:)^2 ,'*') ;
xlabel(' I' );
ylabel(' Var(I) ');

%% 4. Temperature influence
% 1. Shot Noise
% 2. Readout Noise
% 3. Dark Current Noise

src.DeviceTemperature
% set(findall(gcf,'-property','FontSize'),'FontSize',18)