folder  = '.\Records\NoiseAndBackground\old\ShotNoise\Gain20_diffTint';
matfile = [folder '\ShotNoiseVsTint.mat'];
windowSize = 9;

[ records , tintArr] = ChooseRecords(folder , 'WhitePaper*Gain20' , 'Tint');

for tint_i = 1:numel(records)
    rec = ReadRecord(records{tint_i});
    [SN.locSpatNoise(tint_i), SN.globSpatNoise(tint_i), SN.tempNoise(tint_i), SN.meanI(tint_i) ] = CalcNoise(rec,windowSize,[],0);
end
%%    
figure('name',' Var(S)/S vs Tint ' ); 
plot(tintArr,SN.tempNoise.^2./SN.meanI ,'*-');
xlabel('Tint [ ms]' )
ylabel(' Var(S)/<S>')
set(gca,'FontSize',14)
