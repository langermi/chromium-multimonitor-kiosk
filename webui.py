#!/usr/bin/env python3
"""
Web interface for controlling the Chromium Multi-Monitor Kiosk service.
Allows editing of config.sh and urls.ini files through a simple web UI.
"""

import os
import re
import sys
import configparser
from flask import Flask, render_template, request, jsonify, redirect, url_for, flash
from werkzeug.serving import make_server
import threading
import signal

app = Flask(__name__)
app.secret_key = 'kiosk-webui-secret-key-change-in-production'

# Get the directory where this script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_SH_PATH = os.path.join(SCRIPT_DIR, 'config.sh')
URLS_INI_PATH = os.path.join(SCRIPT_DIR, 'urls.ini')

class ConfigManager:
    """Manages reading and writing of configuration files."""
    
    @staticmethod
    def read_config_sh():
        """Read config.sh and extract key configuration variables."""
        config = {}
        try:
            with open(CONFIG_SH_PATH, 'r') as f:
                content = f.read()
                
            # Extract key configuration variables using regex
            patterns = {
                'DEFAULT_URL': r'DEFAULT_URL="([^"]*)"',
                'STRICT_URL_VALIDATION': r'STRICT_URL_VALIDATION=(\w+)',
                'CHECK_INTERVAL': r'CHECK_INTERVAL=(\d+)',
                'REFRESH_INACTIVITY_THRESHOLD': r'REFRESH_INACTIVITY_THRESHOLD=(\d+)',
                'PAGE_REFRESH_INTERVAL': r'PAGE_REFRESH_INTERVAL=(\d+)',
                'DISABLE_PAGE_REFRESH': r'DISABLE_PAGE_REFRESH=(\w+)',
                'NETWORK_READY_TIMEOUT': r'NETWORK_READY_TIMEOUT=(\d+)',
                'NETWORK_READY_CHECK_INTERVAL': r'NETWORK_READY_CHECK_INTERVAL=(\d+)',
                'ENABLE_POWEROFF': r'ENABLE_POWEROFF=(\w+)',
                'POWEROFF_TIME': r'POWEROFF_TIME="([^"]*)"',
                'ENABLE_RESTART': r'ENABLE_RESTART=(\w+)',
                'RESTART_TIME': r'RESTART_TIME="([^"]*)"',
                'APPLY_POWER_SETTINGS': r'APPLY_POWER_SETTINGS=(\w+)',
                'LOG_DEBUG': r'LOG_DEBUG=(\d+)',
                'LOG_FORMAT': r'LOG_FORMAT="([^"]*)"',
                'LOG_TO_JOURNAL': r'LOG_TO_JOURNAL=(\w+)',
                'MAX_LOG_SIZE': r'MAX_LOG_SIZE=\$\(\((\d+)\*1024\*1024\)\)',
                'LOG_MAX_BACKUPS': r'LOG_MAX_BACKUPS=(\d+)',
            }
            
            for key, pattern in patterns.items():
                match = re.search(pattern, content)
                if match:
                    config[key] = match.group(1)
                else:
                    config[key] = ''
                    
        except FileNotFoundError:
            flash(f'Configuration file not found: {CONFIG_SH_PATH}', 'error')
        except Exception as e:
            flash(f'Error reading config.sh: {str(e)}', 'error')
            
        return config
    
    @staticmethod
    def write_config_sh(config):
        """Write updated configuration back to config.sh."""
        try:
            with open(CONFIG_SH_PATH, 'r') as f:
                content = f.read()
            
            # Update each configuration variable
            patterns = {
                'DEFAULT_URL': (r'DEFAULT_URL="[^"]*"', f'DEFAULT_URL="{config.get("DEFAULT_URL", "")}"'),
                'STRICT_URL_VALIDATION': (r'STRICT_URL_VALIDATION=\w+', f'STRICT_URL_VALIDATION={config.get("STRICT_URL_VALIDATION", "true")}'),
                'CHECK_INTERVAL': (r'CHECK_INTERVAL=\d+', f'CHECK_INTERVAL={config.get("CHECK_INTERVAL", "10")}'),
                'REFRESH_INACTIVITY_THRESHOLD': (r'REFRESH_INACTIVITY_THRESHOLD=\d+', f'REFRESH_INACTIVITY_THRESHOLD={config.get("REFRESH_INACTIVITY_THRESHOLD", "300")}'),
                'PAGE_REFRESH_INTERVAL': (r'PAGE_REFRESH_INTERVAL=\d+', f'PAGE_REFRESH_INTERVAL={config.get("PAGE_REFRESH_INTERVAL", "600")}'),
                'DISABLE_PAGE_REFRESH': (r'DISABLE_PAGE_REFRESH=\w+', f'DISABLE_PAGE_REFRESH={config.get("DISABLE_PAGE_REFRESH", "true")}'),
                'NETWORK_READY_TIMEOUT': (r'NETWORK_READY_TIMEOUT=\d+', f'NETWORK_READY_TIMEOUT={config.get("NETWORK_READY_TIMEOUT", "120")}'),
                'NETWORK_READY_CHECK_INTERVAL': (r'NETWORK_READY_CHECK_INTERVAL=\d+', f'NETWORK_READY_CHECK_INTERVAL={config.get("NETWORK_READY_CHECK_INTERVAL", "5")}'),
                'ENABLE_POWEROFF': (r'ENABLE_POWEROFF=\w+', f'ENABLE_POWEROFF={config.get("ENABLE_POWEROFF", "false")}'),
                'POWEROFF_TIME': (r'POWEROFF_TIME="[^"]*"', f'POWEROFF_TIME="{config.get("POWEROFF_TIME", "04:00")}"'),
                'ENABLE_RESTART': (r'ENABLE_RESTART=\w+', f'ENABLE_RESTART={config.get("ENABLE_RESTART", "true")}'),
                'RESTART_TIME': (r'RESTART_TIME="[^"]*"', f'RESTART_TIME="{config.get("RESTART_TIME", "23:00")}"'),
                'APPLY_POWER_SETTINGS': (r'APPLY_POWER_SETTINGS=\w+', f'APPLY_POWER_SETTINGS={config.get("APPLY_POWER_SETTINGS", "true")}'),
                'LOG_DEBUG': (r'LOG_DEBUG=\d+', f'LOG_DEBUG={config.get("LOG_DEBUG", "0")}'),
                'LOG_FORMAT': (r'LOG_FORMAT="[^"]*"', f'LOG_FORMAT="{config.get("LOG_FORMAT", "text")}"'),
                'LOG_TO_JOURNAL': (r'LOG_TO_JOURNAL=\w+', f'LOG_TO_JOURNAL={config.get("LOG_TO_JOURNAL", "true")}'),
                'MAX_LOG_SIZE': (r'MAX_LOG_SIZE=\$\(\(\d+\*1024\*1024\)\)', f'MAX_LOG_SIZE=$(({config.get("MAX_LOG_SIZE", "10")}*1024*1024))'),
                'LOG_MAX_BACKUPS': (r'LOG_MAX_BACKUPS=\d+', f'LOG_MAX_BACKUPS={config.get("LOG_MAX_BACKUPS", "5")}'),
            }
            
            for key, (search_pattern, replacement) in patterns.items():
                content = re.sub(search_pattern, replacement, content)
            
            with open(CONFIG_SH_PATH, 'w') as f:
                f.write(content)
                
            return True
            
        except Exception as e:
            flash(f'Error writing config.sh: {str(e)}', 'error')
            return False
    
    @staticmethod
    def read_urls_ini():
        """Read urls.ini and return URL mappings."""
        urls = {}
        try:
            if os.path.exists(URLS_INI_PATH):
                config = configparser.ConfigParser()
                config.read(URLS_INI_PATH)
                
                if 'urls' in config:
                    urls = dict(config['urls'])
                    
        except Exception as e:
            flash(f'Error reading urls.ini: {str(e)}', 'error')
            
        return urls
    
    @staticmethod
    def write_urls_ini(urls):
        """Write URL mappings back to urls.ini."""
        try:
            config = configparser.ConfigParser()
            config['urls'] = urls
            
            with open(URLS_INI_PATH, 'w') as f:
                config.write(f)
                
            return True
            
        except Exception as e:
            flash(f'Error writing urls.ini: {str(e)}', 'error')
            return False

@app.route('/')
def index():
    """Main dashboard page."""
    config = ConfigManager.read_config_sh()
    urls = ConfigManager.read_urls_ini()
    return render_template('index.html', config=config, urls=urls)

@app.route('/config', methods=['GET', 'POST'])
def config():
    """Configuration editing page."""
    if request.method == 'POST':
        # Handle form submission
        config_data = {}
        for key in request.form:
            config_data[key] = request.form[key]
            
        if ConfigManager.write_config_sh(config_data):
            flash('Configuration updated successfully!', 'success')
        else:
            flash('Failed to update configuration!', 'error')
            
        return redirect(url_for('config'))
    
    # GET request - show the form
    config_data = ConfigManager.read_config_sh()
    return render_template('config.html', config=config_data)

@app.route('/urls', methods=['GET', 'POST'])
def urls():
    """URL mappings editing page."""
    if request.method == 'POST':
        # Handle form submission
        urls_data = {}
        for key in request.form:
            if request.form[key].strip():  # Only add non-empty values
                urls_data[key] = request.form[key].strip()
                
        if ConfigManager.write_urls_ini(urls_data):
            flash('URL mappings updated successfully!', 'success')
        else:
            flash('Failed to update URL mappings!', 'error')
            
        return redirect(url_for('urls'))
    
    # GET request - show the form
    urls_data = ConfigManager.read_urls_ini()
    return render_template('urls.html', urls=urls_data)

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    """REST API endpoint for configuration."""
    if request.method == 'POST':
        config_data = request.json
        success = ConfigManager.write_config_sh(config_data)
        return jsonify({'success': success})
    else:
        config_data = ConfigManager.read_config_sh()
        return jsonify(config_data)

@app.route('/api/urls', methods=['GET', 'POST'])
def api_urls():
    """REST API endpoint for URL mappings."""
    if request.method == 'POST':
        urls_data = request.json
        success = ConfigManager.write_urls_ini(urls_data)
        return jsonify({'success': success})
    else:
        urls_data = ConfigManager.read_urls_ini()
        return jsonify(urls_data)

def run_server(host='0.0.0.0', port=8080, debug=False):
    """Run the Flask development server."""
    app.run(host=host, port=port, debug=debug)

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Chromium Multi-Monitor Kiosk Web UI')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to (default: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=8080, help='Port to bind to (default: 8080)')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    
    args = parser.parse_args()
    
    print(f"Starting Chromium Multi-Monitor Kiosk Web UI on http://{args.host}:{args.port}")
    print(f"Configuration files:")
    print(f"  config.sh: {CONFIG_SH_PATH}")
    print(f"  urls.ini: {URLS_INI_PATH}")
    
    try:
        run_server(host=args.host, port=args.port, debug=args.debug)
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)