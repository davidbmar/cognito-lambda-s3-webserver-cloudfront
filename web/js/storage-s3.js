// S3 Storage Adapter for PCM Recorder
import { encodeWAV, getWAVDuration } from './wav-encoder.js';

export async function createS3Storage({
    apiUrl,
    getAuthToken,
    getUserId,
    enableLocalBackup = true
} = {}) {
    
    // Optional IndexedDB backup
    let localDB = null;
    if (enableLocalBackup) {
        try {
            const { createIndexedDbStorage } = await import('./adapters/storage-indexeddb.js');
            localDB = await createIndexedDbStorage();
        } catch (e) {
            console.warn('Local backup unavailable:', e);
        }
    }
    
    // Active sessions
    const sessions = new Map();
    
    // Generate session ID with timestamp
    const generateSessionId = () => {
        const now = new Date();
        const date = now.toISOString().split('T')[0]; // YYYY-MM-DD
        const time = now.toISOString().split('T')[1].split('.')[0].replace(/:/g, '-'); // HH-MM-SS
        const random = Math.random().toString(36).substring(2, 8);
        return `${date}T${time}-${random}`;
    };
    
    // Upload chunk to S3
    const uploadToS3 = async (wavBlob, sessionId, chunkIndex, durationSeconds) => {
        console.log('🔧 [DEBUG] uploadToS3 called with:', {
            wavBlobSize: wavBlob?.size,
            sessionId,
            chunkIndex,
            durationSeconds,
            apiUrl
        });
        
        const token = getAuthToken();
        if (!token) throw new Error('No authentication token');
        
        const requestBody = {
            sessionId: sessionId,
            chunkNumber: chunkIndex + 1, // API expects 1-based indexing
            contentType: 'audio/wav',
            duration: Math.round(durationSeconds || 10) // use provided duration
        };
        
        console.log('🔧 [DEBUG] Upload chunk request body:', requestBody);
        
        try {
            // Get pre-signed URL
            const response = await fetch(`${apiUrl}/upload-chunk`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });
            
            console.log('🔧 [DEBUG] Pre-signed URL response status:', response.status);
            
            if (!response.ok) {
                const errorText = await response.text();
                console.error('🔧 [DEBUG] Pre-signed URL error response:', errorText);
                throw new Error(`Upload request failed: ${response.status} - ${errorText}`);
            }
            
            const responseData = await response.json();
            console.log('🔧 [DEBUG] Pre-signed URL response:', responseData);
            const { uploadUrl } = responseData;
            
            // Upload to S3
            const uploadResponse = await fetch(uploadUrl, {
                method: 'PUT',
                body: wavBlob,
                headers: {
                    'Content-Type': 'audio/wav'
                }
            });
            
            if (!uploadResponse.ok) throw new Error(`S3 upload failed: ${uploadResponse.status}`);
            
            return true;
        } catch (error) {
            console.error(`Failed to upload chunk ${chunkIndex}:`, error);
            return false;
        }
    };
    
    // Update session metadata
    const updateSessionMetadata = async (sessionId, metadata) => {
        const token = getAuthToken();
        if (!token) return;
        
        try {
            await fetch(`${apiUrl}/session-metadata`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    sessionId: sessionId,
                    metadata: metadata
                })
            });
        } catch (error) {
            console.error('Failed to update session metadata:', error);
        }
    };
    
    return {
        // Required by recorder-box.js
        async putRecording({ id, createdAt, updatedAt, mimeType, status, durationMs }) {
            const sessionId = id || generateSessionId();
            
            sessions.set(sessionId, {
                id: sessionId,
                createdAt,
                updatedAt,
                mimeType,
                status,
                durationMs,
                startTime: Date.now(),
                chunks: [],
                chunkCount: 0
            });
            
            // Initialize session metadata
            await updateSessionMetadata(sessionId, {
                status: status || 'recording',
                createdAt: new Date(createdAt).toISOString(),
                userId: getUserId()
            });
            
            // Also start local backup if available
            if (localDB) {
                await localDB.putRecording({ id, createdAt, updatedAt, mimeType, status, durationMs });
            }
            
            return { id: sessionId };
        },
        
        async setManifest(recordingId, manifest) {
            const session = sessions.get(recordingId);
            if (session) {
                session.manifest = manifest;
            }
            
            if (localDB) {
                await localDB.setManifest(recordingId, manifest);
            }
        },
        
        async setDuration(recordingId, durationMs) {
            const session = sessions.get(recordingId);
            if (session) {
                session.durationMs = durationMs;
            }
            
            if (localDB) {
                await localDB.setDuration(recordingId, durationMs);
            }
        },
        
        async markStatus(recordingId, status) {
            const session = sessions.get(recordingId);
            if (session) {
                session.status = status;
                
                // Update final metadata
                await updateSessionMetadata(recordingId, {
                    status: status,
                    duration: Math.round((session.durationMs || 0) / 1000),
                    chunkCount: session.chunkCount,
                    completedAt: new Date().toISOString()
                });
            }
            
            if (localDB) {
                await localDB.markStatus(recordingId, status);
            }
        },
        
        async startRecording({ recordingId }) {
            const sessionId = recordingId || generateSessionId();
            
            sessions.set(sessionId, {
                id: sessionId,
                startTime: Date.now(),
                chunks: [],
                chunkCount: 0
            });
            
            // Initialize session metadata
            await updateSessionMetadata(sessionId, {
                status: 'recording',
                createdAt: new Date().toISOString(),
                userId: getUserId()
            });
            
            // Also start local backup if available
            if (localDB) {
                await localDB.startRecording({ recordingId: sessionId });
            }
            
            return { recordingId: sessionId };
        },
        
        async putChunk({ recordingId, index, chunkIndex, blob, startMs, endMs }) {
            // Handle both parameter names for compatibility
            const actualChunkIndex = index !== undefined ? index : chunkIndex;
            console.log('🔧 [DEBUG] putChunk called with:', {
                recordingId,
                index,
                chunkIndex,
                actualChunkIndex,
                blobSize: blob?.size,
                startMs,
                endMs
            });
            
            const session = sessions.get(recordingId);
            console.log('🔧 [DEBUG] Session found:', !!session);
            if (!session) throw new Error('Recording session not found');
            
            // Convert Float32Array blob to WAV
            const arrayBuffer = await blob.arrayBuffer();
            const samples = new Float32Array(arrayBuffer);
            console.log('🔧 [DEBUG] Samples length:', samples.length);
            
            const wavBlob = encodeWAV(samples);
            console.log('🔧 [DEBUG] WAV blob size:', wavBlob.size);
            
            // Calculate duration from samples
            const durationSeconds = getWAVDuration(samples);
            console.log('🔧 [DEBUG] Calculated duration:', durationSeconds);
            
            // Upload to S3
            const uploaded = await uploadToS3(wavBlob, recordingId, actualChunkIndex, durationSeconds);
            
            // Track chunk
            const chunkData = {
                index: actualChunkIndex,
                startMs,
                endMs,
                size: wavBlob.size,
                uploaded,
                timestamp: Date.now()
            };
            session.chunks.push(chunkData);
            session.chunkCount++;
            
            console.log('🔧 [DEBUG] Chunk tracked:', chunkData);
            console.log('🔧 [DEBUG] Session now has', session.chunkCount, 'chunks');
            
            // Local backup
            if (localDB) {
                try {
                    await localDB.putChunk({ recordingId, chunkIndex: actualChunkIndex, blob, startMs, endMs });
                    console.log('🔧 [DEBUG] Local backup successful');
                } catch (err) {
                    console.warn('🔧 [DEBUG] Local backup failed:', err.message);
                }
            }
            
            return { size: wavBlob.size, uploaded, wavBlob: wavBlob };
        },
        
        async stopRecording({ recordingId }) {
            const session = sessions.get(recordingId);
            if (!session) return;
            
            const duration = Date.now() - session.startTime;
            
            // Update final metadata
            await updateSessionMetadata(recordingId, {
                status: 'completed',
                duration: Math.round(duration / 1000),
                chunkCount: session.chunkCount,
                completedAt: new Date().toISOString()
            });
            
            // Local backup
            if (localDB) {
                await localDB.stopRecording({ recordingId });
            }
            
            sessions.delete(recordingId);
            
            return {
                recordingId,
                duration,
                chunkCount: session.chunkCount
            };
        },
        
        async listRecordings() {
            // For S3, we'd need to fetch from server
            // For now, return local backup list if available
            if (localDB) {
                return await localDB.listRecordings();
            }
            return [];
        },
        
        async getRecording(recordingId) {
            // Get from local backup if available
            if (localDB) {
                return await localDB.getRecording(recordingId);
            }
            return null;
        },
        
        async deleteRecording(recordingId) {
            // Delete from local backup
            if (localDB) {
                await localDB.deleteRecording(recordingId);
            }
            // S3 deletion would need server API call
        },
        
        async exportRecording(recordingId, format = 'wav') {
            // Export from local backup
            if (localDB) {
                return await localDB.exportRecording(recordingId, format);
            }
            return null;
        }
    };
}