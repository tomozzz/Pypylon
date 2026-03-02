%% Plot Params 
% set here in order to be the same for both patterns
% for speckle vs window size :
winArr = [20,30,50,70,90,110,150,200,250,300,400];
shiftFixed = 0;

% for speckle vs shift  :
shiftArr = 0:7;
windowFixed = 100;
%% Create synthetic Gaussian Pattern
step = 20;
Gwinsize = step;
gaussian_width = 14;
negtive_and_positive = true;

Gwin = gauss2d(Gwinsize,gaussian_width) ;
Im1 = zeros(400);
for x = step/2:step:size(Im1,2)
    for y = step/2:step:size(Im1,1)
        if mod((y+x-step)/step,2)== 0 || negtive_and_positive==false
            Im1(x-Gwinsize/2+1:x+Gwinsize/2,y-Gwinsize/2+1:y+Gwinsize/2) = Gwin;
        else
            Im1(x-Gwinsize/2+1:x+Gwinsize/2,y-Gwinsize/2+1:y+Gwinsize/2) = -Gwin;
        end
    end
end
figure(1); imagesc(Im1); colormap gray;
title('Gaussian Pattern');

%% Plot for Gaussian Pattern speckleSize vs window size and vs shift
figure(2);
subplot(2,1,1);
% winArr = [20,30,50,70,90,110,150,200,250,300,400]
% shiftFixed = 0;

k=1;
speckleSize = nan(size(winArr));
for win = winArr
    imcut = Im2(shiftFixed+(1:win), shiftFixed+(1:win) );
    [ speckleSize(k) ] = FindSpeckleSize(imcut);
    k=k+1;
end
plot(winArr, speckleSize,'*-'); 
title(['Gaussian Pattern Speckle Size vs window size (shift=' num2str(shiftFixed) ')'] )
xlabel('Speckle Size'); ylabel('window size')

subplot(2,1,2);
% shiftArr = 0:7;
% windowFixed = 100;
k=1;
speckleSize = nan(size(shiftArr));
for shift=shiftArr
    imcut = Im2(shift+(1:windowFixed), shift+(1:windowFixed) );
    [ speckleSize(k) ] = FindSpeckleSize(imcut);
    k=k+1;
end

plot(shiftArr, speckleSize,'*-'); 
title(['Gaussian Pattern Speckle Size vs shift (window=' num2str(windowFixed) ')'])
xlabel('Speckle Size'); ylabel('window size')

%% Create synthetic Schach-Board Pattern
step = 10;
Im2 = zeros(400);
for x=0:step:size(Im2,2)-step
    for y=0:step:size(Im2,1)-step
        if mod((y+x)/step,2)== 1
            Im2(x+1:x+step,y+1:y+step) = 10;
        end
    end
end
figure(3); imagesc(Im2); colormap gray;
title('Gaussian Pattern');

%% Plot for Schach-Board Pattern speckleSize vs window size and vs shift
figure(4);
subplot(2,1,1);

% winArr = [20,30,50,70,90,110,150,200,250,300,400]
% shiftFixed = 0;

k=1;
speckleSize = nan(size(winArr));
for win = winArr
    imcut = Im2(shiftFixed+(1:win), shiftFixed+(1:win) );
    [ speckleSize(k) ] = FindSpeckleSize(imcut);
    k=k+1;
end
plot(winArr, speckleSize,'*-');
title(['Schach-Board Pattern Speckle Size vs window size (shift=' num2str(shiftFixed) ')'] )
xlabel('Speckle Size'); ylabel('window size')

subplot(2,1,2);
% shiftArr = 0:7;
% windowFixed = 100;
k=1;
speckleSize = nan(size(shiftArr));
for shift=shiftArr
    imcut = Im2(shift+(1:windowFixed), shift+(1:windowFixed) );
    [ speckleSize(k) ] = FindSpeckleSize(imcut);
    k=k+1;
end

plot(shiftArr, speckleSize,'*-'); 
title(['Schach-Board Pattern Speckle Size vs shift (window=' num2str(windowFixed) ')'])
xlabel('Speckle Size'); ylabel('window size')