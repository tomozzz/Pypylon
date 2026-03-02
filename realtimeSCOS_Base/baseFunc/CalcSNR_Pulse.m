function [SNR,  spectrum , freq, pulseFreq, pulseBPM] = CalcSNR_Pulse(Sig,Fs,plotFlag)
% Sig - sinal in time. Fs - Frame rate (Hz)

  if nargin < 3
      plotFlag = false;
  end

  if plotFlag
      plotFrequencyStart = 0.2;
  else
      plotFrequencyStart = [];
  end
  [ spectrum , freq] = abs_fft(Sig,Fs,plotFrequencyStart);

   maxDCfreq = 0.65;
   if Fs > 11
       maxExpectedPulseFreq = 5;
   elseif Fs > 3.2
       maxExpectedPulseFreq = Fs/2*0.8;
   else 
      maxExpectedPulseFreq = Inf; % Can't calculate noise
   end
   
   % ignore DC
   spectrum(freq < maxDCfreq ) = [];
   freq(freq < maxDCfreq ) = [];
   
   [ Signal , maxIdx ] = max(spectrum);
   if maxIdx == 1 
       warning('Maximum FFT value found in unexpected frequency %g Hz', freq(maxIdx))
   end
       
   if freq(maxIdx) >  maxExpectedPulseFreq  
       warning('Maximum FFT value found in unexpected frequency %g Hz', freq(maxIdx))
   end
   
   pulseFreq = freq(maxIdx);
   pulseBPM   = round(pulseFreq*60,1);
   
   Noise = mean( spectrum( freq > maxExpectedPulseFreq ) );
   SNR = Signal/Noise;

