function mask = CreateCircleMask(imSize,R,Yc,Xc)
    if nargin<2
        R = floor(min(imSize)/2-1);
    end
    if nargin<4
        if nargin==3
            error('If Xc passed you need to path Yc as well')
        end
        Xc = imSize(2)/2 + 0.5;
        Yc = imSize(1)/2 + 0.5;
    end
    [x,y] = meshgrid(1:imSize(2),1:imSize(1));
    mask = ((x-Xc).^2 + (y-Yc).^2 )<= R^2 ;
