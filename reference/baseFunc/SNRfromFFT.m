function [SNR, Sig, Noise, SigFreq ] = SNRfromFFT(freq,spectrum)
   maxDCfreq = 0.25;
   maxExpectedPulseFreq = 3.2;
   
   % ignore DC
   spectrum(freq < maxDCfreq ) = [];
   freq(freq < maxDCfreq ) = [];
   
   [ Sig , maxIdx ] = max(spectrum(freq < maxExpectedPulseFreq));
   if maxIdx == 1 
       error('Maximum FFT value found in unexpected frequency %g Hz', freq(maxIdx))
   end
       
   if maxIdx == nnz(freq < maxExpectedPulseFreq) 
       error('Maximum FFT value found in unexpected frequency %g Hz', freq(maxIdx))
   end
   
   SigFreq = freq(maxIdx);
   Noise = mean( spectrum( freq > maxExpectedPulseFreq ) );
   SNR = Sig/Noise;
end