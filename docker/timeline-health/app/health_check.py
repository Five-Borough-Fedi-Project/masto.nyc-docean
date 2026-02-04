#!/usr/bin/env python3
"""
Timeline Health Check

Connects to a Mastodon instance's public timeline API to check if recent posts exist.
If the latest post is within the specified freshness threshold, sends a GET request
to a health check URL (e.g., BetterStack heartbeat).

Usage:
    python -m app.health_check --hostname masto.nyc --freshness 3000 --heartbeat-url https://uptime.betterstack.com/api/v1/heartbeat/xxx

Environment variables can also be used:
    MASTODON_HOSTNAME: The Mastodon instance hostname (e.g., masto.nyc)
    FRESHNESS_THRESHOLD: Maximum age in seconds for posts to be considered fresh (default: 3000)
    HEARTBEAT_URL: URL to GET when timeline is healthy
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Optional

import requests


def get_latest_public_post(hostname: str) -> Optional[dict]:
    """
    Fetch the latest post from the public timeline.
    
    Uses the REST API endpoint /api/v1/timelines/public which returns
    an array of Status objects.
    
    Args:
        hostname: The Mastodon instance hostname
    
    Returns:
        The latest status dict, or None if unavailable
    """
    timeline_url = f"https://{hostname}/api/v1/timelines/public"
    params = {
        "remote": "false",      # Include local posts
        "only_media": "false",  # Don't filter by media
        "limit": 1              # We only need the most recent one
    }
    
    try:
        response = requests.get(timeline_url, params=params, timeout=30)
        response.raise_for_status()
        statuses = response.json()
        
        if statuses and len(statuses) > 0:
            return statuses[0]
        else:
            print("No posts found on public timeline")
            return None
            
    except requests.exceptions.RequestException as e:
        print(f"Error fetching public timeline: {e}")
        return None
    except json.JSONDecodeError as e:
        print(f"Error parsing timeline response: {e}")
        return None


def parse_mastodon_datetime(datetime_str: str) -> datetime:
    """
    Parse a Mastodon datetime string to a timezone-aware datetime.
    
    Mastodon uses ISO 8601 format: 2026-02-04T02:04:59.000Z
    
    Args:
        datetime_str: ISO 8601 datetime string
        
    Returns:
        Timezone-aware datetime object
    """
    # Handle various ISO 8601 formats
    # Remove 'Z' suffix and replace with +00:00 for Python compatibility
    if datetime_str.endswith('Z'):
        datetime_str = datetime_str[:-1] + '+00:00'
    
    return datetime.fromisoformat(datetime_str)


def check_timeline_freshness(hostname: str, freshness_threshold: int) -> bool:
    """
    Check if the timeline has fresh posts.
    
    Args:
        hostname: The Mastodon instance hostname
        freshness_threshold: Maximum age in seconds for posts to be considered fresh
        
    Returns:
        True if the latest post is within the freshness threshold
    """
    latest_post = get_latest_public_post(hostname)
    
    if latest_post is None:
        print("Could not retrieve latest post - timeline check failed")
        return False
    
    post_id = latest_post.get("id", "unknown")
    created_at_str = latest_post.get("created_at")
    
    if not created_at_str:
        print(f"Post {post_id} has no created_at field")
        return False
    
    try:
        post_time = parse_mastodon_datetime(created_at_str)
        now = datetime.now(timezone.utc)
        age_seconds = (now - post_time).total_seconds()
        
        print(f"Latest post ID: {post_id}")
        print(f"Post created at: {created_at_str}")
        print(f"Post age: {age_seconds:.1f} seconds")
        print(f"Freshness threshold: {freshness_threshold} seconds")
        
        if age_seconds <= freshness_threshold:
            print(f"✓ Timeline is FRESH (post is {age_seconds:.1f}s old, threshold is {freshness_threshold}s)")
            return True
        else:
            print(f"✗ Timeline is STALE (post is {age_seconds:.1f}s old, threshold is {freshness_threshold}s)")
            return False
            
    except ValueError as e:
        print(f"Error parsing post datetime '{created_at_str}': {e}")
        return False


def send_heartbeat(heartbeat_url: str) -> bool:
    """
    Send a GET request to the heartbeat URL.
    
    Args:
        heartbeat_url: The URL to ping for health check signal
        
    Returns:
        True if the request was successful
    """
    try:
        response = requests.get(heartbeat_url, timeout=30)
        response.raise_for_status()
        print(f"✓ Heartbeat sent successfully to {heartbeat_url}")
        print(f"  Response: {response.status_code}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to send heartbeat: {e}")
        return False


def main():
    """Main entry point for the health check."""
    parser = argparse.ArgumentParser(
        description="Check Mastodon timeline health and send heartbeat if healthy"
    )
    parser.add_argument(
        "--hostname",
        type=str,
        default=os.environ.get("MASTODON_HOSTNAME", ""),
        help="Mastodon instance hostname (e.g., masto.nyc)"
    )
    parser.add_argument(
        "--freshness",
        type=int,
        default=int(os.environ.get("FRESHNESS_THRESHOLD", "3000")),
        help="Maximum age in seconds for posts to be considered fresh (default: 3000)"
    )
    parser.add_argument(
        "--heartbeat-url",
        type=str,
        default=os.environ.get("HEARTBEAT_URL", ""),
        help="URL to GET when timeline is healthy"
    )
    
    args = parser.parse_args()
    
    # Validate required arguments
    if not args.hostname:
        print("Error: --hostname is required (or set MASTODON_HOSTNAME env var)")
        sys.exit(1)
    
    if not args.heartbeat_url:
        print("Error: --heartbeat-url is required (or set HEARTBEAT_URL env var)")
        sys.exit(1)
    
    print(f"=" * 60)
    print(f"Timeline Health Check")
    print(f"=" * 60)
    print(f"Hostname: {args.hostname}")
    print(f"Freshness threshold: {args.freshness} seconds")
    print(f"Heartbeat URL: {args.heartbeat_url}")
    print(f"=" * 60)
    
    # Check timeline freshness
    print("\n[1/2] Checking timeline freshness...")
    is_fresh = check_timeline_freshness(args.hostname, args.freshness)
    
    if not is_fresh:
        print("\n[2/2] Skipping heartbeat - timeline is stale")
        print("\n" + "=" * 60)
        print("✗ Health check FAILED - timeline is stale")
        print("=" * 60)
        sys.exit(1)
    
    # Timeline is fresh - send heartbeat
    print("\n[2/2] Sending heartbeat...")
    if send_heartbeat(args.heartbeat_url):
        print("\n" + "=" * 60)
        print("✓ Health check PASSED - heartbeat sent")
        print("=" * 60)
        sys.exit(0)
    else:
        print("\n" + "=" * 60)
        print("✗ Health check FAILED - could not send heartbeat")
        print("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
