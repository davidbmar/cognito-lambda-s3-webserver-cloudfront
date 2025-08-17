// WAV Encoder - Converts Float32Array PCM data to WAV format
export function encodeWAV(samples, sampleRate = 48000, numChannels = 1) {
    const length = samples.length * numChannels;
    const buffer = new ArrayBuffer(44 + length * 2);
    const view = new DataView(buffer);
    
    // WAV header
    const writeString = (offset, string) => {
        for (let i = 0; i < string.length; i++) {
            view.setUint8(offset + i, string.charCodeAt(i));
        }
    };
    
    // Convert Float32 [-1, 1] to Int16 [-32768, 32767]
    const floatTo16BitPCM = (output, offset, input) => {
        for (let i = 0; i < input.length; i++, offset += 2) {
            const s = Math.max(-1, Math.min(1, input[i]));
            output.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
        }
    };
    
    // RIFF header
    writeString(0, 'RIFF');
    view.setUint32(4, 36 + length * 2, true);
    writeString(8, 'WAVE');
    
    // fmt chunk
    writeString(12, 'fmt ');
    view.setUint32(16, 16, true); // fmt chunk size
    view.setUint16(20, 1, true); // PCM format
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * numChannels * 2, true); // byte rate
    view.setUint16(32, numChannels * 2, true); // block align
    view.setUint16(34, 16, true); // bits per sample
    
    // data chunk
    writeString(36, 'data');
    view.setUint32(40, length * 2, true);
    
    // Convert samples
    floatTo16BitPCM(view, 44, samples);
    
    return new Blob([buffer], { type: 'audio/wav' });
}

// Helper to get duration in seconds
export function getWAVDuration(samples, sampleRate = 48000) {
    return samples.length / sampleRate;
}