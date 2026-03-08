function [ P1 , freq ] = abs_fft(S,Fs,plotFrequencyStart)
% Calculate one sided FFT
% -----------------------
% Input :
%   S  - signal
%   Fs - sampling frequency 
%   plotFrequencyStart - if not empty, graph will be plotted , starting from this frequency
% Output :
%   P1 - single-sided amplitude spectrum
%   freq - frequency vector corresponding to P1


if mod(length(S),2)==1
    S(end) = [];
end

T = 1/Fs;             % Sampling period       
if mod(length(S),2)~=0
    S(end) = [];
end
L = length(S);        % Length of signal

time = (0:L-1)*T;        % Time vector

% Compute the Fourier transform of the signal. 
Y = fft(S);

% Compute the two-sided spectrum P2. Then compute the single-sided spectrum P1 based on P2 and the even-valued signal length L.
P2 = abs(Y/L);
P1 = P2(1:L/2+1);
P1(2:end-1) = 2*P1(2:end-1);

% Define the frequency domain f and plot the single-sided amplitude spectrum P1.
freq = Fs*(0:(L/2))/L;
if ~isempty(plotFrequencyStart)
    figure;
    subplot(2,1,1)
    plot(time,S)
    title('Original Signal')
    xlabel('t[s]')
    ylabel('S(t)')
    
    subplot(2,1,2)
    plot(freq,P1)
    title('Single-Sided Amplitude Spectrum of S(t)')
    xlabel('f(Hz)')
    ylabel('|FFT(f)|');
    xlim([plotFrequencyStart freq(end)])
end

