function [FWHM,AC,XX,curve]= Speckle_ACF_calc_dry(Frm_stack,limitfactor)
%  Speckle Size Measure by Marco Leonetti. 06/24/2021
%  takes  frame (or  stack of frames organized in x-y-FrameIndex) as input and performs the
%  autocorrelation in x-y employng the Fourier tranform apporach. The resulting
%  autocorrelation frame is averaged out for each input frame of the stack.
%  After autocorrelation maxima is found, I compute the radial averaging.
%  On the radial average of the AC I perform Guassian fit to extract sigma
%  and from that the FWHM.
%


%  [Frm_stack] : the input is a 3-d or 2-d matrix containing the speckles in the format x,y,,frame-index
%  [FWHM] : Full width at half maximum of the speckle size (obtained with Gaussian fitting)
%  [AC XX] : Profile of the autocorrelation of the speckle frame; "plot(XX,AC)" to visaulize it
%  [curve] : result of the fit.to visaulize it  "hold on;  plot(curve)"

if nargin < 2
    limitfactor = 1; % Set your default value here
end
          

%% Get input metadata
Frm_stack=double(Frm_stack);
SZ_stack=size(Frm_stack); % Get input size
[row,col] = size(Frm_stack,1:2);

if numel(SZ_stack)==3
    Nframes=(SZ_stack(3));
elseif numel(SZ_stack)==2
    Nframes=1;
end


%% Calculating AVG 2D ACF
ACFrm_avg=zeros(row,col); 
P = row*col;
for i=1:Nframes
    current_frame=Frm_stack(:,:,i); % Get curent frame
    current_frame=current_frame-mean2(current_frame); % Remove DC
    ACFrm=abs(fftshift(ifft2( abs( fft2(current_frame) ).^2 )))./P;  % Calculating 2DACF of current frame
    ACFrm_avg=ACFrm_avg+ACFrm; % Add to avg sum
end
ACFrm_avg=ACFrm_avg/max(ACFrm_avg,[],'all'); %normalization
[~, linearIndex] = max(ACFrm_avg(:));
[MaxrowIndex, MaxcolumnIndex] = ind2sub(size(ACFrm_avg), linearIndex);

%% Calculating Speckle size with respect of the autocorrelation maxima (Cnt)

[AC, XX]=radial_avg2(ACFrm_avg, [MaxrowIndex,MaxcolumnIndex],limitfactor);

%% Gaussian fit

fo = fitoptions('Method','NonlinearLeastSquares','StartPoint',[  4 min(AC)]); % if the fit results not working touch here starpoint of the fit 
ft = fittype(' (1-b)*exp( -(x.^2./(2*(S^2)) )  )+b ','options',fo);  %% fit with a gaussian with baseline, better can be done exploiting a bessel function
[curve,~] = fit(XX',AC',ft);
Sigma=curve.S;  % retrieving Sigma

%% output
FWHM=2*sqrt(2*log(2))*Sigma;     %Full width at half Maximum of the speckle size in pixels
%% final visualizing
% AC_img=ACFrm_avg;
% 
% figure(fig_handle);
% subplot(1,4,1);
% imagesc(current_frame);colormap('default');axis equal;
% impixelinfo;
% axis off
% title('Last speckle')
% 
% subplot(1,4,2)
% imagesc(AC_img);colormap('default');axis equal;
% impixelinfo;
% axis off
% title('Autocorr')
% 
% subplot(1,4,3)
% imagesc(abs(fftshift(fft2(ifftshift(AC_img)))).^.1);colormap('default');axis equal;
% impixelinfo;
% title('FT')
% 
% subplot(1,4,4)
% plot(XX,AC)
% hold on
% plot(curve)
% XLIM=min([FWHM*4  max(XX) ]);
% xlim([0 XLIM])
% ylabel('Autocorelation')
% xlabel('R (pixels)')
% 
% title(strcat('FWHM = ',num2str(FWHM)) );
% hold off;


