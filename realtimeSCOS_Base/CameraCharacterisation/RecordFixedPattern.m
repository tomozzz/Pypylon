addpath('.\baseFunc')
noiseFolder = '..\Records\NoiseAndBackground\Basler_1440GS_Vika01\Mono8\FixedPattern';
%% 1. From Laser
setupParams.Phantom = '0.68%';

fixedPatternFolder = [ noiseFolder '\Phantom_IL' setupParams.Phantom filesep 'vsGainvsExpT_halfLaserPower_ObjectivePlanNx20Close'];

setupParams.Camera = 'Basler_acA1440-220um_SN40335401';
setupParams.Objective = 'Edmunds_PlanN_x20';
setupParams.ObjectiveLocation = 'Close';
setupParams.Lens = 'None';
setupParams.SDS = "1.7cm";
setupParams.FiberCollect = '400um';
setupParams.FiberFromLaser = '62.5um';
setupParams.LaserPulsed = 'No';
setupParams.LaserPower = '60mW';
setupParams.addToFilename = false;

nOfFrames = 500;
prefix = ''; %ObjectivePlanNx20Close';
recFormat = '.tiff';

camParams = struct();
camParams.AcquisitionFrameRate = 100;
camParams.addToFilename.AcquisitionFrameRate = false;
camParams.videoFormat = 'Mono8';
camParams.addToFilename.videoFormat = false;


overwriteFlag = false;
gainArr = [20 30 35];% [ 0:10:30 , 35];
expTArr = [1 3 5 7 10 15 20 25]*1e3; 
suffix = '';
setupParams.Table = 'OpticsTable';

camParams.Gain = 20;
camParams.ExposureTime = 10000;
im = RecordFromCamera(1, camParams, [],[],[],[],[],[],0);
[ full_mask , circ ] = GetROI(im);
roi_half_size = ceil(circ.Radius) + 10 ;
roi = [ round(circ.Center(2)) + (-roi_half_size:roi_half_size) ;
        round(circ.Center(1)) + (-roi_half_size:roi_half_size) ];
mask        = full_mask(roi(1,:)  , roi(2,:));
%%
for gain = gainArr(:)'
    for expt = expTArr(:)'
        camParams.Gain = gain;
        camParams.ExposureTime = expt;
        im = RecordFromCamera(1, camParams, [],[],[],[],[],[],0);
        meanI = mean2(im(full_mask));
        N = histcounts(im(full_mask),0:255);  
        if N(end) > numel(im)*0.0001 || meanI > 240 % check saturation
            break;
        end
        fprintf('Mean = %g\n',meanI);
        if meanI < 3
            continue;
        end
        [rec  ] = RecordFromCamera(nOfFrames, camParams); %, setupParams , fixedPatternFolder , recFormat, prefix, suffix, overwriteFlag , 0 );
        recName = sprintf('%s%s%s_Gain%gdB_expT%gms%s',fixedPatternFolder,filesep,prefix,gain,round(expt/1e3,1),suffix); 
        info.cam = camParams; info.setup = setupParams;
        mkdir(recName);
        prettyjson(info,[recName '\info.json']);
        full_im = mean(rec,3);
        im = full_im( roi(1,:)  , roi(2,:));
        if mean2(im(mask)) > 252; error('Image is saturated!'); end
        fprintf('Recorded Mean = %g\n',mean2(im));
        %delete([recName '\*.tiff']);

        save([recName filesep 'average_im.mat'],'im','mask');
    end
end
clear gain expt rec

%% Analyze

ContrastArr = cell(1,numel(gainArr));
expTlist = cell(1,numel(gainArr));
window = 7;
MeanIArr= cell(1,numel(gainArr));
for gain_i = 1:numel(gainArr(:))
    [ records, expTlist{gain_i} ] = ChooseRecords(fixedPatternFolder,['*Gain' num2str(gainArr(gain_i)) 'dB*'],'expT'); 
    for k = 1:numel(expTlist{gain_i})
        RR = load([records{k} '\average_im.mat']);
        meanIm = imfilter(RR.im, true(window)/window^2,'conv' );
        contrastMat =  ( stdfilt(RR.im,ones(window)) ./ meanIm ) .^ 2;
        ContrastArr{gain_i}(k) = mean(contrastMat(RR.mask) );
        MeanIArr{gain_i}(k) = mean2(RR.im(RR.mask));
    end
end
%
[~,gainArr] = ChooseRecords(fixedPatternFolder,'*Gain*dB*','Gain') ;
gainArr = unique(gainArr);
f1=figure('Units','Normalized','Position',[0.1 0.1 0.8 0.7]);
subplot(1,3,1);
for gain_i = 1:numel(gainArr(:))
   plot(expTlist{gain_i},ContrastArr{gain_i},'*-') ; hold on
end
legend(strcat({'Gain '} , num2cellstr(gainArr), 'dB'),'location','best');
title('Contrast')
ylabel('Contrast var(I)/<I>^2');
xlabel('Exposure Time [ms]')

% f2=figure;
subplot(1,3,2);
for gain_i = 1:numel(gainArr(:))
   plot(expTlist{gain_i},MeanIArr{gain_i},'*-') ; hold on
end
legend(strcat({'Gain '} , num2cellstr(gainArr), 'dB'),'location','best');
ylabel('<I> [DU]');
xlabel('Exposure Time [ms]');
title('mean Intensity')
savefig(f1,[fixedPatternFolder '\ContrastVsExpT.fig' ])

subplot(1,3,3);
for gain_i = 1:numel(gainArr(:))
   plot(MeanIArr{gain_i},ContrastArr{gain_i},'*') ; hold on
end
legend(strcat({'Gain '} , num2cellstr(gainArr), 'dB'),'location','best');
ylabel('Contrast');
xlabel('<I> [DU]')
title('Contrast Vs Intensity')
%% 2A. From White paper - Loop Over Gain and ExpT
fixedPatternFolder =  [ noiseFolder '\WhitePaper_GainAndExpT' ];

setupParams.Camera = 'Basler_acA1440-220um_SN40335401';
setupParams.DistanceToPaper = '4cm';
setupParams.Lens = 'None';
setupParams.addToFilename = false;
setupParams.Table = 'VikaPC';

nOfFrames = 100;
prefix = 'WhitePaper';
recFormat = '.tiff';

camParams = struct();
camParams.AcquisitionFrameRate = 100;
camParams.addToFilename.AcquisitionFrameRate = false;
camParams.videoFormat = 'Mono8';
camParams.addToFilename.videoFormat = false;


overwriteFlag = false;
gainArr = 0:5:35;
expTArr = [1 5 10 15 20 25]*1e3; 
suffix = 'Light2';

for gain = gainArr(:)'
    for expt = expTArr(:)'
        camParams.Gain = gain;
        camParams.ExposureTime = expt;
        im = RecordFromCamera(1, camParams, [],[],[],[],[],[],0);
        meanI = mean2(im);
        N = histcounts(im(:),256);  
        if N(end) > numel(im)*0.0001 || meanI > 240 % check saturation
            break;
        end
        fprintf('Mean = %g\n',meanI);
        if meanI < 3
            continue;
        end
        [rec , recName ] = RecordFromCamera(nOfFrames, camParams, setupParams , fixedPatternFolder , recFormat, prefix, suffix, overwriteFlag , 1 );
        im = mean(rec,3);
        if mean2(im) > 252; error('Image is saturated!'); end
        fprintf('Recorded Mean = %g\n',mean2(im));
        delete([recName '\*.tiff']);

        save([recName filesep 'average_im.mat'],'im');
    end
end
clear gain expt rec
%% Analyze
ContrastArr = cell(1,numel(gainArr));
expTlist = cell(1,numel(gainArr));
window = 7;
MeanIArr= cell(1,numel(gainArr));
for gain_i = 1:numel(gainArr(:))
    [ records, expTlist{gain_i} ] = ChooseRecords(fixedPatternFolder,['*Gain' num2str(gainArr(gain_i)) 'dB*'],'expT'); 
    for k = 1:numel(expTlist{gain_i})
        RR = load([records{k} '\average_im.mat']);
        meanIm = imfilter(RR.im, true(window)/window^2,'conv' );
        ContrastArr{gain_i}(k) = mean2( ( stdfilt(RR.im,ones(window)) ./ meanIm ) .^ 2 );
        MeanIArr{gain_i}(k) = mean2(RR.im);
    end
end

figure;
for gain_i = 1:numel(gainArr(:))
   plot(expTlist{gain_i},ContrastArr{gain_i},'*-') ; hold on
end
legend(strcat({'Gain '} , num2cellstr(gainArr), 'dB'),'location','best');
ylabel('Contrast var(I)/<I>^2');
xlabel('Exposure Time [ms]')

figure;
for gain_i = 1:numel(gainArr(:))
   plot(expTlist{gain_i},MeanIArr{gain_i},'*-') ; hold on
end
legend(strcat({'Gain '} , num2cellstr(gainArr), 'dB'),'location','best');
ylabel('<I>');
xlabel('Exposure Time [ms]')
%%
figure;
for gain_i = 1:numel(gainArr(:))
   plot(MeanIArr{gain_i},ContrastArr{gain_i},'*') ; hold on
end
legend(strcat({'Gain '} , num2cellstr(gainArr), 'dB'),'location','best');
ylabel('Contrast');
xlabel('<I> [DU]')


%% From White paper - Same Intensity
fixedPatternFolder = [ noiseFolder '\WhitePaper_SameIntensity4' ];

setupParams.Camera = 'Basler_acA1440-220um_SN40335401';
setupParams.DistanceToPaper = '4cm';
setupParams.Lens = 'None';
setupParams.addToFilename = false;
setupParams.Table = 'VikaPC';

nOfFrames = 100;
prefix = 'WhitePaper';
recFormat = '.tiff';

camParams = struct();
camParams.AcquisitionFrameRate = 100;
camParams.addToFilename.AcquisitionFrameRate = false;
camParams.videoFormat = 'Mono8';
camParams.addToFilename.videoFormat = false;
camParams.BlackLevel = 0;

 
overwriteFlag = true;
plotFlag = false;
gainArr = 0:5:35;
expTArr = [1 5 10 15 20 25]*1e3; 
suffix = 'Light3';
setupParams.Light = 5;
goalI = 140; % DU
allowed_error = 1; % DU

last_expt = 1e3/1.1;
max_iterations = 20;

for gain = gainArr(:)'
    fprintf([ suffix ' ; Gain = ' num2str(gain) 'dB \n------------------------------------------------------\n'])
    camParams.Gain = gain;
    
    expt = round(last_expt*1.1);
%     fprintf('exposure Time = %gms\t:',expt*1e-3);
    camParams.ExposureTime = expt;
    im = RecordFromCamera(1, camParams, [],[],[],[],[],[],0);
    measuredI = mean2(im);
    fprintf('MeanI = %g\n',measuredI);
    
    n=2;
    while abs( goalI - measuredI ) > allowed_error && n < max_iterations
        expt = round(expt*( goalI/measuredI ));
%         fprintf(['exposure Time = ' num2str(expt/1000) 'ms\t:']);
        camParams.ExposureTime = expt;
        im = RecordFromCamera(1, camParams,[],[],[],[],[],[],0 );
        measuredI = mean2(im);
        fprintf('MeanI = %g\n',measuredI);                      
    end
    if n == max_iterations 
        error('Too much iterations -> check search algorithm!!!');
    end
    [rec , recName ] = RecordFromCamera(nOfFrames, camParams, setupParams , fixedPatternFolder , recFormat, prefix, suffix, overwriteFlag , plotFlag );
    delete([recName '\*.tiff']);
    im = mean(rec,3);
    fprintf('==> Final MeanI = %g\n',mean2(im));     
    save([recName filesep 'average_im.mat'],'im');
    last_expt = expt ;
end
clear rec
%% Analyse 
%% 1. Biuld BP table:
records = dir(fixedPatternFolder); records(1:2)=[];
ind_forBP = [1,5,numel(records)];

totBPArr = cell(1,numel(ind_forBP));
spatialBP = cell(1,numel(ind_forBP));
temporalBP = cell(1,numel(ind_forBP));
for i = 1:numel(ind_forBP)
    bprec = ReadRecord( [ fixedPatternFolder filesep records(ind_forBP(i)).name ] );
    [totBPArr{i}, spatialBP{i}, temporalBP{i}] = FindBadPixels(bprec,[],[],[],[],1);
end
 
totBP = false(size(totBPArr{1}));
for i = 1:numel(totBPArr)
    totBP = totBP | totBPArr{i};
end

figure; imshowpair(spatialBP{1},spatialBP{2})
figure; imshowpair(temporalBP{3},temporalBP{2})
nnz(spatialBP{2} & spatialBP{1})
nnz(spatialBP{2})
nnz(spatialBP{1})
%% 1. Can You Fix known intensity?
[ records, gainArr ] = ChooseRecords(fixedPatternFolder,'*Gain*','Gain'); 
window = 7;
RR = load([records{4} filesep 'average_im.mat']);  
Im1 = RR.im;
[FixedStd,OrigStd] = InitNaN(size(records));
for k=1:numel(records)
   RR = load([records{k} filesep 'average_im.mat']); 
   OrigStd(k) = mean2( stdfilt(RR.im,ones(window)) );
   FixedStd(k) = mean2( stdfilt(RR.im-Im1,ones(window)) );
end

figure; plot(gainArr,OrigStd,'o'); hold on
plot(gainArr,FixedStd,'*');
legend('Original','Fixed');
%%
[ records, gainArr ]   = ChooseRecords( [ noiseFolder '\WhitePaper_SameIntensity3' ],'*Gain*','Gain'); 
[ records2, gainArr2 ] = ChooseRecords( [ noiseFolder '\WhitePaper_SameIntensity4' ],'*Gain*','Gain'); 
if ~isequal(gainArr,gainArr2); error('records should be the same'); end

window = 7;
RR = load([records{4} filesep 'average_im.mat']);  
Im1 = RR.im;
[FixedStd,OrigStd,meanI1,meanI2] = InitNaN(size(records));
for k=1:numel(records)
   RR = load([records{k} filesep 'average_im.mat']); 
   RR2 = load([records2{k} filesep 'average_im.mat']);
   OrigStd(k) = mean2( stdfilt(RR.im,ones(window)) );
   FixedStd(k) = mean2( stdfilt(RR.im-RR2.im,ones(window)) );
   meanI1(k) = mean2(RR.im);
   meanI2(k) = mean2(RR2.im);
end
meanI1'
meanI2'
figure; plot(gainArr,OrigStd,'o'); hold on
plot(gainArr,FixedStd,'*');
legend('Original','Fixed');

%% 2. Can you fix by Gain


