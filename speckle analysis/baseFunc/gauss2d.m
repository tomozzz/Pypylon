function mat = gauss2d(gsize, sigma, center)
if numel(gsize)==1 ; gsize(2) = gsize(1); end 
if nargin < 3; center = round(gsize/2); end
[x,y] = ndgrid(1:gsize(1), 1:gsize(2));
mat = (exp(-((x-center(1)).^2 + (y-center(2)).^2)./(2*sigma)));
