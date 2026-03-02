analysisFolder = ['C:\Users\' getenv('username') '\OneDrive - Bar-Ilan University - Students\PhD Research\SCOS\Records\NoiseAndBackground\Basler_1440GS_Vika01\Mono8\FixedPattern'];
shotNoise1Folder = [ analysisFolder filesep 'ShotNoise\vsExpTvsGain_1'];
shotNoise1_matfile = [shotNoise1Folder filesep 'shotNoiseVsGainVsExpt.mat'];
videoFormat = 'Mono12';
nOfBits = str2double(videoFormat(5:end));
windowSize = 9;

nOfFrames = 300;
setupParams.Background = 'WhitePaper'; %#ok<UNRCH>
setupParams.Intensity  = 25; % at gain=0dB expT = 1000us
if ~exist(shotNoise1Folder,'dir'); mkdir(shotNoise1Folder); end
prefix = 'WhitePaper'; suffix =['Inensity' num2str(setupParams.Intensity)];
recFormat = '.tiff';
SN1.expTArr = [0.5 1 3 5 7 ]*1e3;
if nOfBits == 12
    SN1.gainArr = [0:10:20,24];
elseif  nOfBits == 8
    SN1.gainArr = [0:5:30,36];
end
overwriteFlag = true;
plotFlag = false;
camParams = struct();
camParams.AcquisitionFrameRate = 100;
camParams.BlackLevel = 0;

    vid = videoinput("gentl", 1, videoFormat);
    files = cell(numel(SN1.gainArr), numel(SN1.expTArr));
 %%
    for gain_i = 1:numel(SN1.gainArr)
        gain = SN1.gainArr(gain_i);
        break_from_this_gain = false;
        for expt_i = 1:numel(SN1.expTArr)
            %%
            expT = SN1.expTArr(expt_i);
            if break_from_this_gain; continue; end
            camParams.Gain = gain;
            camParams.ExposureTime = expT;
            im = RecordFromCamera(1, camParams,[],'','','','',0,1,vid);
            hst = histcounts(im(:),0:2^nOfBits);
            if hst(end) > numel(im)*0.001 % image saturated
                break_from_this_gain = true; % continue for all the other expT
                continue;
            end
            rec = RecordFromCamera(nOfFrames, camParams, setupParams , shotNoise1Folder  , recFormat, prefix, suffix, overwriteFlag , plotFlag , vid);  
            [SN1.locSpatNoise(gain_i,expt_i), SN1.globSpatNoise(gain_i,expt_i), SN1.tempNoise(gain_i,expt_i), SN1.meanI(gain_i,expt_i) ] = ...
                CalcNoise(rec,windowSize,[],0);
            SN1.gainMat(gain_i,expt_i) = gain;
            SN1.expTMat(gain_i,expt_i) = expT;
            %%
        end
    end
    SN1.meanI(gain_i,expt_i) = SN1.meanI(gain_i,expt_i) - camParams.BlackLevel;
    delete(vid);
    clear gain expT camParams
    
    save(shotNoise1_matfile,'-struct','SN1')


%%
camParams = struct();
camParams.AcquisitionFrameRate = 100;
setupParams.Intensity  = 50; % at gain=0dB expT = 1000us
setupParams.addToFilename = true;
camParams.Gain = 0;
camParams.ExposureTime = 7000;
camParams.videoFormat = 'Mono12';
rec = RecordFromCamera(nOfFrames, camParams, setupParams , shotNoise1Folder  , recFormat, prefix, '', overwriteFlag , 1 );  

%%
% gain = 10;
% files = dir([shotNoise1Folder '\*Gain10*']);
% 
% for file_i = 1:numel(files)
%     rec = ReadRecord([ shotNoise1Folder filesep files(file_i).name]);
%     tmpNoiseIm = std(rec,0,3);
%     SN1.tempNoise(file_i) = mean(tmpNoiseIm);
%     SN1.meanI(file_i) = mean(rec,'All');
% end
% 
% plot(SN1.meanI(:) , SN1.tempNoise(:)^2 ,'*') ;
% xlabel(' I' );
% ylabel(' Var(I) ');
