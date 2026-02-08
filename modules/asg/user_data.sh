#!/bin/bash
set -e

# Update system
yum update -y

# Install required packages
yum install -y python3 python3-pip postgresql15 git

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Create application directory
mkdir -p /opt/webapp
cd /opt/webapp

# Create Flask application
cat > app.py << 'EOF'
from flask import Flask, render_template_string, request, jsonify
import psycopg2
import os
import boto3
from datetime import datetime

app = Flask(__name__)

# Database configuration
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_NAME = os.environ.get('DB_NAME', 'webappdb')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')
DB_PORT = os.environ.get('DB_PORT', '5432')

# S3 configuration
S3_BUCKET = os.environ.get('S3_BUCKET', '')
s3_client = boto3.client('s3') if S3_BUCKET else None

def get_db_connection():
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT,
            connect_timeout=10
        )
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        return None

@app.route('/')
def index():
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>3-Tier Web Application</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                max-width: 800px;
                margin: 50px auto;
                padding: 20px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }
            .container {
                background: rgba(255, 255, 255, 0.1);
                backdrop-filter: blur(10px);
                border-radius: 15px;
                padding: 30px;
                box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
            }
            h1 { color: #fff; text-align: center; }
            .status { 
                background: rgba(255, 255, 255, 0.2);
                padding: 15px;
                border-radius: 8px;
                margin: 10px 0;
            }
            .success { color: #4ade80; }
            .error { color: #f87171; }
            button {
                background: #4ade80;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 5px;
                cursor: pointer;
                font-size: 16px;
                margin: 5px;
            }
            button:hover { background: #22c55e; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 3-Tier Web Application</h1>
            <div class="status">
                <h2>System Status</h2>
                <p><strong>Instance ID:</strong> {{ instance_id }}</p>
                <p><strong>Timestamp:</strong> {{ timestamp }}</p>
                <p><strong>Database:</strong> <span class="{{ db_status_class }}">{{ db_status }}</span></p>
                <p><strong>S3 Bucket:</strong> {{ s3_bucket }}</p>
            </div>
            <div style="text-align: center; margin-top: 20px;">
                <button onclick="location.reload()">🔄 Refresh</button>
                <button onclick="testDB()">🗄️ Test Database</button>
                <button onclick="testS3()">📦 Test S3</button>
            </div>
            <div id="results" style="margin-top: 20px;"></div>
        </div>
        <script>
            async function testDB() {
                const results = document.getElementById('results');
                results.innerHTML = '<p>Testing database connection...</p>';
                try {
                    const response = await fetch('/api/db-test');
                    const data = await response.json();
                    results.innerHTML = '<div class="status"><pre>' + JSON.stringify(data, null, 2) + '</pre></div>';
                } catch (error) {
                    results.innerHTML = '<div class="status"><p class="error">Error: ' + error.message + '</p></div>';
                }
            }
            async function testS3() {
                const results = document.getElementById('results');
                results.innerHTML = '<p>Testing S3 connection...</p>';
                try {
                    const response = await fetch('/api/s3-test');
                    const data = await response.json();
                    results.innerHTML = '<div class="status"><pre>' + JSON.stringify(data, null, 2) + '</pre></div>';
                } catch (error) {
                    results.innerHTML = '<div class="status"><p class="error">Error: ' + error.message + '</p></div>';
                }
            }
        </script>
    </body>
    </html>
    """
    
    import socket
    instance_id = socket.gethostname()
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Test database connection
    conn = get_db_connection()
    if conn:
        db_status = "✅ Connected"
        db_status_class = "success"
        conn.close()
    else:
        db_status = "❌ Disconnected"
        db_status_class = "error"
    
    s3_bucket = S3_BUCKET if S3_BUCKET else "Not configured"
    
    return render_template_string(html, 
        instance_id=instance_id,
        timestamp=timestamp,
        db_status=db_status,
        db_status_class=db_status_class,
        s3_bucket=s3_bucket
    )

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat()
    }), 200

@app.route('/api/db-test')
def db_test():
    conn = get_db_connection()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute('SELECT version();')
            version = cur.fetchone()[0]
            cur.close()
            conn.close()
            return jsonify({
                'status': 'success',
                'message': 'Database connection successful',
                'version': version
            })
        except Exception as e:
            return jsonify({
                'status': 'error',
                'message': str(e)
            }), 500
    else:
        return jsonify({
            'status': 'error',
            'message': 'Could not connect to database'
        }), 500

@app.route('/api/s3-test')
def s3_test():
    if not s3_client:
        return jsonify({
            'status': 'error',
            'message': 'S3 not configured'
        }), 500
    
    try:
        response = s3_client.list_objects_v2(Bucket=S3_BUCKET, MaxKeys=5)
        return jsonify({
            'status': 'success',
            'message': 'S3 connection successful',
            'objects_count': response.get('KeyCount', 0)
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
EOF

# Create systemd service
cat > /etc/systemd/system/webapp.service << EOF
[Unit]
Description=3-Tier Web Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/webapp
Environment="DB_HOST=${db_endpoint}"
Environment="DB_NAME=${db_name}"
Environment="DB_USER=${db_username}"
Environment="DB_PASSWORD=${db_password}"
Environment="S3_BUCKET=${s3_bucket}"
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Install Python dependencies
pip3 install flask psycopg2-binary boto3

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/webapp/app.log",
                        "log_group_name": "${log_group}",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Enable and start webapp service
systemctl daemon-reload
systemctl enable webapp
systemctl start webapp

# Wait for service to start
sleep 10

# Check service status
systemctl status webapp --no-pager || true

