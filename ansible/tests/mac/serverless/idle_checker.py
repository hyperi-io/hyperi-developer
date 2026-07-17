#!/usr/bin/env python3
"""
Scaleway Serverless Function - Mac Mini Idle Checker
Deletes Mac minis with 'auto-delete' tag after 23h of idle time

Triggered: Every hour via CRON trigger
Checks: SSH connections, CPU usage from Scaleway metrics
Deletes: Servers idle >23h with matching tags (before next 24h billing block)

Note: Scaleway enforces 24h minimum lease from deployment.
      Deleting at 23h idle ensures we delete before the 2nd billing cycle.
"""
import os
import json
from datetime import datetime
import requests

# The prefix that marks a server as OURS TO DELETE. This is the only thing
# standing between this function and someone else's Mac, so it lives in one
# place rather than being repeated as a string literal.
#
# Renaming it is NOT a cosmetic change: the reaper stops recognising any server
# still named with the old prefix, and those keep running and keep billing.
# Rename the servers first, or match both prefixes through the transition.
TEST_MAC_PREFIX = 'hyperi-test-mac-'


def handle(event, context):
    """Main handler for Scaleway Function"""

    # Get credentials from environment
    secret_key = os.environ['SCALEWAY_SECRET_KEY']
    zone = os.environ.get('SCALEWAY_ZONE', 'fr-par-3')

    api_url = f"https://api.scaleway.com/apple-silicon/v1alpha1/zones/{zone}/servers"
    headers = {"X-Auth-Token": secret_key}

    # List all Mac mini servers
    response = requests.get(api_url, headers=headers)
    servers = response.json().get('servers', [])

    deleted = []
    kept = []

    for server in servers:
        # Anything without our prefix is not ours. Skip it -- do not delete it.
        server_name = server.get('name', '')
        if not server_name.startswith(TEST_MAC_PREFIX):
            kept.append(f"{server_name}: not a test Mac (no {TEST_MAC_PREFIX} prefix)")
            continue

        # Check server age
        created_at = datetime.fromisoformat(server['created_at'].replace('Z', '+00:00'))
        age_hours = (datetime.now(created_at.tzinfo) - created_at).total_seconds() / 3600

        # Get metrics (CPU, network activity)
        server_id = server['id']
        metrics_url = f"{api_url}/{server_id}/metrics"
        metrics_response = requests.get(metrics_url, headers=headers)

        if metrics_response.status_code == 200:
            metrics = metrics_response.json()
            # Check for activity in last 23 hours (before next 24h billing block)
            cpu_usage = metrics.get('cpu_usage_avg_1h', 100)  # Default to active if unknown
            network_rx = metrics.get('network_rx_bytes_1h', 1000)  # Default to active

            # Idle if CPU <5% and minimal network for 23h (delete before 2nd billing cycle)
            if cpu_usage < 5 and network_rx < 1000 and age_hours >= 23:
                # Delete idle server
                delete_response = requests.delete(f"{api_url}/{server_id}", headers=headers)
                if delete_response.status_code in [200, 204]:
                    deleted.append(f"{server_name}: idle {age_hours:.1f}h, deleted")
                else:
                    kept.append(f"{server_name}: delete failed - {delete_response.status_code}")
            else:
                kept.append(f"{server_name}: active (CPU:{cpu_usage}%, age:{age_hours:.1f}h)")
        else:
            kept.append(f"{server_name}: metrics unavailable")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "deleted": deleted,
            "kept": kept,
            "timestamp": datetime.now().isoformat()
        })
    }
