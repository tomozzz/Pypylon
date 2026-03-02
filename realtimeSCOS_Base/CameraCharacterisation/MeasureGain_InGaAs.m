% shotNoiseFolder = '..\Records\NoiseAndBackground\Basler_1440GS_Vika01\Mono8\FixedPattern\ShotNoise\vsExpTvsGain_1';
% recShortName = 'WhitePaper_BackgroundWhitePaper_Intensity50_FR100Hz_Gain0dB_expT3ms_000';
shotNoiseFolder = 'C:\Users\tarlevi\OneDrive - Bar-Ilan University - Students\PhD Research\InGaAs\NIT Camera\Records\GainHigh_Measurement_no_NUC2';

expT = 15;
BlackLevel = 0;
nBits = 14;
gainLowHigh = 'High';
BlackLevelDark = 0;
max_capacity = 17e3;

records = dir([shotNoiseFolder '\Gain' gainLowHigh '_expT' num2str(expT) 'ms_I*']);
darkRecFile = dir([shotNoiseFolder '\Gain' gainLowHigh '_expT' num2str(expT) 'ms_Dark*']);
darkRec = ReadRecord([shotNoiseFolder filesep darkRecFile.name ],100);
darkIm = mean( darkRec , 3) - BlackLevelDark;
darkVar = mean2(std(darkRec,0,3));
%%
[IPerRec , spPerRec , spPerRec_std] = InitNaN([1,numel(records)]);
for ri = 1:numel(records)
    disp(records(ri).name)
    recName = fullfile(shotNoiseFolder,records(ri).name);
    rec = ReadRecord(recName,100);
    nFrames = size(rec,3);
    mean(rec(:))
        
    Ivec = nan(1,nFrames-1); spVec = nan(1,nFrames-1);  Idiff=nan(1,nFrames-1); 
    for i = 1:nFrames-1
       Ivec(i) = mean2(rec(:,:,i) - darkIm - BlackLevel ); 
       im_diff = rec(:,:,i+1)-rec(:,:,i); 
       Idiff(i) = mean2(im_diff);
       spVec(i) = var(im_diff(:))/2 - darkVar;
    end
    
    spPerRec(ri) = mean(spVec);
    spPerRec_std(ri) = std(spVec);
    IPerRec(ri) = mean(Ivec);
    figure; 
    subplot(2,1,1); plot(Ivec); title([ records(ri).name ],'interpreter','none'); ylabel('<I> [DU]')
    subplot(2,1,2); plot(spVec); ylabel('var [DU]')    
end
% clear rec
%%
fig = figure; 
errorbar(IPerRec,spPerRec,spPerRec_std,'bo'); xlabel('<I> [DN]'); ylabel('\sigma^2 [DN^2]');
title(['AnalogGain = ' num2str(gainLowHigh) 'dB, Exposure Time = ' num2str(expT) 'ms '])
p = polyfit(IPerRec,spPerRec,1);
hold on;
plot([0 IPerRec], polyval(p,[0 IPerRec]),'--r');
ylims = ylim;
xlims = xlim;
G = p(1) % 0.0238 , % 5.8750 for 24dB 20ms 12bits % 5.8617 for 24dB 15ms 12bits

% Gcalc = 2^8/10.5e3 % 0.0244    
Gcalc = 2^nBits/max_capacity  

text(xlims(2)*0.1 , ylims(2)* 0.8 ,{['Slope = ' num2str(G,3)],['CalcG = 2^{' num2str(nBits) '}/capacity * 10^{g[dB]/20}= ' num2str(Gcalc,3)]});


save([ shotNoiseFolder filesep 'Results_Gain' num2str(gainLowHigh) '_expT' num2str(expT) 'ms.mat' ],...
    'IPerRec','spPerRec','spPerRec_std','expT','nBits','gainLowHigh','Gcalc','G','BlackLevel','BlackLevelDark')
savefig(fig,[ shotNoiseFolder filesep 'Results_Gain' num2str(gainLowHigh) 'dB_expT' num2str(expT) 'ms.fig' ]);


    