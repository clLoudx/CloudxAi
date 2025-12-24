import pytest
from unittest.mock import AsyncMock

from app.db.session import get_db


@pytest.mark.asyncio
async def test_readiness_check_db_failure_with_override(client):
    # Prepare a mock session whose execute raises
    mock_session = AsyncMock()
    mock_session.execute.side_effect = Exception("Simulated DB failure")

    # Override the dependency on the client.app (TestClient)
    def override_get_db():
        return mock_session

    client.app.dependency_overrides[get_db] = override_get_db

    try:
        response = client.get('/api/v1/readyz')
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'not ready'
        assert data['database'] == 'disconnected'
    finally:
        client.app.dependency_overrides.pop(get_db, None)
