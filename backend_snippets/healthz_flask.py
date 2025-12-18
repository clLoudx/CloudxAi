# Minimal Flask health endpoint (add to your app)
from flask import Blueprint, jsonify
health = Blueprint('health', __name__)
@health.route('/healthz', methods=['GET'])
def healthz():
    return jsonify({"status":"ok"}), 200
# register with app: app.register_blueprint(health)
