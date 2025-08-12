#!/bin/bash

# Cleanup script for audio and transcript files
# Usage: ./cleanup-audio-files.sh

USER_ID="01ebc530-5041-7042-936c-6e516c3a0d20"
BUCKET="dbm-cf-2-web"

echo "==================================="
echo "Audio & Transcript Cleanup Tool"
echo "==================================="
echo

# List all audio sessions
echo "📁 Your Audio Sessions:"
aws s3 ls s3://$BUCKET/users/$USER_ID/audio/sessions/ | while read line; do
    SESSION=$(echo $line | awk '{print $2}' | tr -d '/')
    if [ ! -z "$SESSION" ]; then
        CHUNK_COUNT=$(aws s3 ls s3://$BUCKET/users/$USER_ID/audio/sessions/$SESSION --recursive | grep -c ".webm")
        SIZE=$(aws s3 ls s3://$BUCKET/users/$USER_ID/audio/sessions/$SESSION --recursive --summarize | grep "Total Size" | awk '{print $3}')
        SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc 2>/dev/null || echo "0")
        echo "  • $SESSION - $CHUNK_COUNT chunks, ${SIZE_MB}MB"
    fi
done

echo
echo "📄 Your Transcripts:"
TRANSCRIPT_COUNT=$(aws s3 ls s3://$BUCKET/users/$USER_ID/transcripts/ | wc -l)
echo "  Total: $TRANSCRIPT_COUNT transcript files"

echo
echo "==================================="
echo "Cleanup Options:"
echo "==================================="
echo "1. Delete all audio sessions except today's"
echo "2. Delete all transcripts"
echo "3. Delete specific session (enter session ID)"
echo "4. Delete all audio and transcripts"
echo "5. Show detailed file list"
echo "6. Exit"
echo
read -p "Enter your choice (1-6): " choice

case $choice in
    1)
        echo "Deleting all audio sessions except today's..."
        TODAY=$(date +%Y-%m-%d)
        aws s3 ls s3://$BUCKET/users/$USER_ID/audio/sessions/ | while read line; do
            SESSION=$(echo $line | awk '{print $2}' | tr -d '/')
            if [[ ! "$SESSION" =~ ^$TODAY ]]; then
                echo "  Deleting: $SESSION"
                aws s3 rm s3://$BUCKET/users/$USER_ID/audio/sessions/$SESSION --recursive
            fi
        done
        echo "✅ Old audio sessions deleted"
        ;;
    
    2)
        echo "Deleting all transcripts..."
        aws s3 rm s3://$BUCKET/users/$USER_ID/transcripts/ --recursive
        echo "✅ All transcripts deleted"
        ;;
    
    3)
        read -p "Enter session ID to delete: " SESSION_ID
        echo "Deleting session: $SESSION_ID"
        aws s3 rm s3://$BUCKET/users/$USER_ID/audio/sessions/$SESSION_ID/ --recursive
        aws s3 rm s3://$BUCKET/users/$USER_ID/transcripts/ --recursive --exclude "*" --include "*$SESSION_ID*"
        echo "✅ Session deleted"
        ;;
    
    4)
        read -p "Are you sure you want to delete ALL audio and transcripts? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "Deleting all audio..."
            aws s3 rm s3://$BUCKET/users/$USER_ID/audio/ --recursive
            echo "Deleting all transcripts..."
            aws s3 rm s3://$BUCKET/users/$USER_ID/transcripts/ --recursive
            echo "✅ All audio and transcripts deleted"
        else
            echo "Cancelled"
        fi
        ;;
    
    5)
        echo "Detailed file list:"
        echo
        echo "Audio files:"
        aws s3 ls s3://$BUCKET/users/$USER_ID/audio/ --recursive --human-readable | head -20
        echo
        echo "Transcript files:"
        aws s3 ls s3://$BUCKET/users/$USER_ID/transcripts/ --human-readable
        ;;
    
    6)
        echo "Exiting..."
        exit 0
        ;;
    
    *)
        echo "Invalid choice"
        ;;
esac

echo
echo "Current storage usage:"
TOTAL_SIZE=$(aws s3 ls s3://$BUCKET/users/$USER_ID/ --recursive --summarize | grep "Total Size" | awk '{print $3}')
TOTAL_MB=$(echo "scale=2; $TOTAL_SIZE / 1048576" | bc 2>/dev/null || echo "0")
echo "Total: ${TOTAL_MB}MB"