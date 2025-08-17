// chunk-player.js - Dual-mode WAV player for individual chunks and continuous sessions
export class ChunkPlayer {
    constructor() {
        this.currentAudio = null;
        this.currentPlayingId = null;
        this.sessionAudio = null; // For continuous session playback
        this.isPlayingSession = false;
    }

    // Create audio element from WAV blob
    createAudioElement(wavBlob, chunkId) {
        const audioUrl = URL.createObjectURL(wavBlob);
        const audio = new Audio(audioUrl);
        
        audio.addEventListener('ended', () => {
            this.currentPlayingId = null;
            this.updatePlayButton(chunkId, false);
            URL.revokeObjectURL(audioUrl);
        });
        
        audio.addEventListener('error', (e) => {
            console.error('Audio playback error:', e);
            this.currentPlayingId = null;
            this.updatePlayButton(chunkId, false);
            URL.revokeObjectURL(audioUrl);
        });
        
        return { audio, audioUrl };
    }

    // Play or pause a chunk
    async playChunk(wavBlob, chunkId) {
        console.log('🎵 [DEBUG] Playing chunk:', chunkId);
        
        // Stop current audio if playing different chunk
        if (this.currentAudio && this.currentPlayingId !== chunkId) {
            this.currentAudio.pause();
            this.updatePlayButton(this.currentPlayingId, false);
            this.currentAudio = null;
            this.currentPlayingId = null;
        }
        
        // Toggle current chunk
        if (this.currentPlayingId === chunkId) {
            if (this.currentAudio) {
                if (this.currentAudio.paused) {
                    await this.currentAudio.play();
                    this.updatePlayButton(chunkId, true);
                } else {
                    this.currentAudio.pause();
                    this.updatePlayButton(chunkId, false);
                }
            }
            return;
        }
        
        // Play new chunk
        const { audio, audioUrl } = this.createAudioElement(wavBlob, chunkId);
        this.currentAudio = audio;
        this.currentPlayingId = chunkId;
        
        try {
            await audio.play();
            this.updatePlayButton(chunkId, true);
        } catch (error) {
            console.error('Failed to play audio:', error);
            this.currentPlayingId = null;
            URL.revokeObjectURL(audioUrl);
        }
    }

    // Update play button appearance
    updatePlayButton(chunkId, isPlaying) {
        const button = document.querySelector(`[data-chunk-id="${chunkId}"] .play-button`);
        if (button) {
            const icon = button.querySelector('.play-icon');
            if (icon) {
                icon.innerHTML = isPlaying ? this.getPauseIcon() : this.getPlayIcon();
            }
            button.title = isPlaying ? 'Pause' : 'Play';
        }
    }

    // Stop all playback
    stopAll() {
        if (this.currentAudio) {
            this.currentAudio.pause();
            this.currentAudio = null;
        }
        if (this.currentPlayingId) {
            this.updatePlayButton(this.currentPlayingId, false);
            this.currentPlayingId = null;
        }
        this.stopSession();
    }

    // Stop session playback
    stopSession() {
        if (this.sessionAudio) {
            this.sessionAudio.pause();
            this.sessionAudio = null;
        }
        this.isPlayingSession = false;
        this.updateSessionPlayButton(false);
    }

    // Concatenate WAV blobs for continuous playback (inspired by player-mse.js)
    async concatenateWavBlobs(chunkBlobs) {
        console.log('🎵 [DEBUG] Concatenating WAV blobs:', chunkBlobs.length);
        
        if (chunkBlobs.length === 0) {
            throw new Error('No chunks to concatenate');
        }
        
        if (chunkBlobs.length === 1) {
            return chunkBlobs[0]; // Single chunk, return as-is
        }

        // Parse WAV headers and extract PCM data from each chunk
        const pcmDataArrays = [];
        let totalSamples = 0;
        let sampleRate = 48000; // Default
        
        for (const wavBlob of chunkBlobs) {
            const arrayBuffer = await wavBlob.arrayBuffer();
            const dataView = new DataView(arrayBuffer);
            
            // Read WAV header to get sample rate and data size
            const chunkSize = dataView.getUint32(4, true);
            const sampleRateFromHeader = dataView.getUint32(24, true);
            const dataSize = dataView.getUint32(40, true);
            
            sampleRate = sampleRateFromHeader; // Use sample rate from WAV
            
            // Extract PCM data (skip 44-byte WAV header)
            const pcmData = new Int16Array(arrayBuffer, 44, dataSize / 2);
            pcmDataArrays.push(pcmData);
            totalSamples += pcmData.length;
        }
        
        console.log('🎵 [DEBUG] Total samples to concatenate:', totalSamples);
        
        // Create concatenated PCM data
        const concatenatedPcm = new Int16Array(totalSamples);
        let offset = 0;
        
        for (const pcmData of pcmDataArrays) {
            concatenatedPcm.set(pcmData, offset);
            offset += pcmData.length;
        }
        
        // Create new WAV blob with concatenated data
        return this.createWavBlob(concatenatedPcm, sampleRate);
    }

    // Create WAV blob from PCM data
    createWavBlob(pcmData, sampleRate = 48000) {
        const numChannels = 1;
        const bytesPerSample = 2;
        const blockAlign = numChannels * bytesPerSample;
        const byteRate = sampleRate * blockAlign;
        const dataSize = pcmData.length * bytesPerSample;
        
        const buffer = new ArrayBuffer(44 + dataSize);
        const view = new DataView(buffer);
        
        // WAV header
        this.writeString(view, 0, 'RIFF');
        view.setUint32(4, 36 + dataSize, true);
        this.writeString(view, 8, 'WAVE');
        this.writeString(view, 12, 'fmt ');
        view.setUint32(16, 16, true);
        view.setUint16(20, 1, true); // PCM format
        view.setUint16(22, numChannels, true);
        view.setUint32(24, sampleRate, true);
        view.setUint32(28, byteRate, true);
        view.setUint16(32, blockAlign, true);
        view.setUint16(34, 16, true); // 16-bit
        this.writeString(view, 36, 'data');
        view.setUint32(40, dataSize, true);
        
        // Copy PCM data
        const pcmView = new Int16Array(buffer, 44);
        pcmView.set(pcmData);
        
        return new Blob([buffer], { type: 'audio/wav' });
    }

    // Helper to write string to DataView
    writeString(view, offset, string) {
        for (let i = 0; i < string.length; i++) {
            view.setUint8(offset + i, string.charCodeAt(i));
        }
    }

    // Play continuous session from multiple chunks
    async playSession(chunkBlobs, sessionId = 'session') {
        console.log('🎵 [DEBUG] Playing session with', chunkBlobs.length, 'chunks');
        
        try {
            // Stop any current playback
            this.stopAll();
            
            // Concatenate all WAV chunks
            const sessionWav = await this.concatenateWavBlobs(chunkBlobs);
            console.log('🎵 [DEBUG] Session WAV size:', sessionWav.size);
            
            // Create and play session audio
            const audioUrl = URL.createObjectURL(sessionWav);
            this.sessionAudio = new Audio(audioUrl);
            this.isPlayingSession = true;
            
            this.sessionAudio.addEventListener('ended', () => {
                this.stopSession();
                URL.revokeObjectURL(audioUrl);
            });
            
            this.sessionAudio.addEventListener('error', (e) => {
                console.error('Session audio playback error:', e);
                this.stopSession();
                URL.revokeObjectURL(audioUrl);
            });
            
            await this.sessionAudio.play();
            this.updateSessionPlayButton(true);
            
            return { success: true, duration: this.sessionAudio.duration };
            
        } catch (error) {
            console.error('Failed to play session:', error);
            this.stopSession();
            return { success: false, error: error.message };
        }
    }

    // Update session play button state
    updateSessionPlayButton(isPlaying) {
        const button = document.getElementById('btnPlaySession');
        if (button) {
            const icon = button.querySelector('.play-icon');
            const text = button.querySelector('.play-text');
            
            if (icon) {
                icon.innerHTML = isPlaying ? this.getPauseIcon() : this.getPlayIcon();
            }
            if (text) {
                text.textContent = isPlaying ? 'Stop Session' : 'Play Session';
            }
            button.title = isPlaying ? 'Stop continuous playback' : 'Play entire session continuously';
        }
    }

    // Icon helpers
    getPlayIcon() {
        return `
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                <polygon points="5,3 19,12 5,21"/>
            </svg>
        `;
    }

    getPauseIcon() {
        return `
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                <rect x="6" y="4" width="4" height="16"/>
                <rect x="14" y="4" width="4" height="16"/>
            </svg>
        `;
    }

    // Get upload status icon
    getUploadStatusIcon(status) {
        switch (status) {
            case 'uploaded':
                return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" style="color: #22c55e">
                    <polyline points="20,6 9,17 4,12" stroke="currentColor" stroke-width="2" fill="none"/>
                </svg>`;
            case 'uploading':
                return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" style="color: #3b82f6">
                    <path d="M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z"/>
                </svg>`;
            case 'failed':
                return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" style="color: #ef4444">
                    <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none"/>
                    <line x1="15" y1="9" x2="9" y2="15" stroke="currentColor" stroke-width="2"/>
                    <line x1="9" y1="9" x2="15" y2="15" stroke="currentColor" stroke-width="2"/>
                </svg>`;
            default:
                return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" style="color: #6b7280">
                    <circle cx="12" cy="12" r="3"/>
                </svg>`;
        }
    }
}