function [ A , A_without_shift ]  = Autocorrelation2D(I)
%Original author: Tristan Ursell. See FEX code: https://www.mathworks.com/matlabcentral/fileexchange/67348-autocorr2d
% Tristan's code was modified to include padding
 
% get size of image
[N, M] = size(I);
% find the next power of two for each side of image
In = 2^nextpow2(N);
Im = 2^nextpow2(M);
I = double(I); %convert to double
I = I-mean(I(:)); %subtract mean
I = I/sqrt(sum(I(:).^2)); %normalize magnitude
fft_I = fft2(I, In, Im); %compute fft2 by zero-padding

A_without_shift = real( ifft2(fft_I.*conj(fft_I), In, Im)  );
A =  fftshift( A_without_shift ); %compute autocorrelation
end
