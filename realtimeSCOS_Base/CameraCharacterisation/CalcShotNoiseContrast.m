recName = 'D:\SCOS\Records\U-type\Itralipid0.68%\SDS33mm_gain30dB_expT5ms_FR100Hz_500frames';

rec = ReadRecord(recName,300);
clear rec
im  = mean(rec,3);

clear mask
load([recName '\Mask.mat']);


windowSize = 9;
roi_half_size = ceil((c.Radius+windowSize));
roi = [ round(c.Center(2)) + (-roi_half_size:roi_half_size) ;
        round(c.Center(1)) + (-roi_half_size:roi_half_size) ];
cut_mask        = mask(roi(1,:)  , roi(2,:));

cut_im   = im(  roi(1,:)  , roi(2,:));
roi_half_size = ceil((c.Radius+windowSize));


meanFrame = mean(cut_im(cut_mask));
stdIm = stdfilt(cut_im,true(windowSize));
fixedPatternVar = mean(stdIm(cut_mask))^2
fixedPatternContrast = rawSpeckleVar/meanFrame^2

bitDepth =8;
satCapacity = 10.5e3;
G = ConvertGain(ExtractParametersFromString(recName,'gain'),bitDepth,satCapacity)

shotNoiseVar = G * meanFrame
shotNoiseContrast = G/meanFrame

totBGContrast = fixedPatternContrast + shotNoiseContrast

