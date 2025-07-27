#!/usr/bin/env python3
"""
S3 File Downloader Script
Searches for files in the S3 bucket and downloads them to a temp directory.
Handles Unicode characters in filenames properly.
"""

import boto3
import sys
import os
import unicodedata
import argparse
from pathlib import Path

def normalize_filename(filename):
    """Normalize filename to handle Unicode characters"""
    # Normalize Unicode characters
    normalized = unicodedata.normalize('NFKC', filename)
    return normalized

def search_and_download_file(bucket_name, search_term, download_dir='/tmp'):
    """
    Search for files containing the search term and download them
    """
    s3 = boto3.client('s3')
    
    try:
        # List all objects in the bucket
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket_name)
        
        matching_files = []
        
        print(f"Searching for files containing '{search_term}' in bucket '{bucket_name}'...")
        
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    key = obj['Key']
                    # Search in the key (file path)
                    if search_term.lower() in key.lower():
                        matching_files.append({
                            'key': key,
                            'size': obj['Size'],
                            'modified': obj['LastModified']
                        })
        
        if not matching_files:
            print(f"No files found matching '{search_term}'")
            return []
        
        print(f"\nFound {len(matching_files)} matching file(s):")
        for i, file_info in enumerate(matching_files, 1):
            print(f"{i}. {file_info['key']} ({file_info['size']} bytes, modified: {file_info['modified']})")
        
        # Create download directory if it doesn't exist
        os.makedirs(download_dir, exist_ok=True)
        
        downloaded_files = []
        
        for file_info in matching_files:
            key = file_info['key']
            
            # Create a safe filename for local storage
            filename = os.path.basename(key)
            if not filename:  # Handle directory keys
                filename = key.replace('/', '_')
            
            # Normalize the filename
            normalized_filename = normalize_filename(filename)
            
            # Create local file path
            local_path = os.path.join(download_dir, normalized_filename)
            
            print(f"\nDownloading '{key}' to '{local_path}'...")
            
            try:
                s3.download_file(bucket_name, key, local_path)
                print(f"✅ Downloaded successfully: {local_path}")
                downloaded_files.append(local_path)
            except Exception as e:
                print(f"❌ Failed to download '{key}': {e}")
        
        return downloaded_files
        
    except Exception as e:
        print(f"Error accessing S3: {e}")
        return []

def main():
    parser = argparse.ArgumentParser(description='Search and download files from S3 bucket')
    parser.add_argument('search_term', help='Search term to find files')
    parser.add_argument('--bucket', default='dbm-cf-2-web', help='S3 bucket name (default: dbm-cf-2-web)')
    parser.add_argument('--download-dir', default='/tmp', help='Download directory (default: /tmp)')
    
    args = parser.parse_args()
    
    print(f"S3 File Downloader")
    print(f"Bucket: {args.bucket}")
    print(f"Search term: {args.search_term}")
    print(f"Download directory: {args.download_dir}")
    print("-" * 50)
    
    downloaded_files = search_and_download_file(args.bucket, args.search_term, args.download_dir)
    
    if downloaded_files:
        print(f"\n✅ Successfully downloaded {len(downloaded_files)} file(s):")
        for file_path in downloaded_files:
            print(f"  - {file_path}")
    else:
        print("\n❌ No files were downloaded")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 download-s3-file.py <search_term> [--bucket bucket_name] [--download-dir /path/to/dir]")
        print("Example: python3 download-s3-file.py 'Screenshot' --download-dir /tmp")
        sys.exit(1)
    
    main()