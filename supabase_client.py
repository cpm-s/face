import json
import os
import time
from typing import Any, Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from facefusion import logger, supabase_config

SESSION : Dict[str, Any] = {}
TIMEOUT = 15


class SupabaseError(Exception):
	pass


def is_configured() -> bool:
	return bool(supabase_config.get_supabase_url() and supabase_config.get_supabase_key())


def request(method : str, url : str, payload : Optional[Any] = None, headers : Optional[Dict[str, str]] = None) -> Any:
	data = json.dumps(payload).encode() if payload is not None else None
	http_request = Request(url, data = data, method = method, headers = headers or {})

	try:
		with urlopen(http_request, timeout = TIMEOUT) as response: #nosec
			body = response.read()
			return json.loads(body) if body else None
	except HTTPError as exception:
		raise SupabaseError(str(exception.code) + ' ' + exception.read().decode(errors = 'ignore')) from exception
	except (URLError, TimeoutError) as exception:
		raise SupabaseError(str(exception)) from exception


def sign_in() -> None:
	email = os.getenv('SUPABASE_EMAIL')
	password = os.getenv('SUPABASE_PASSWORD')

	if not email or not password:
		raise SupabaseError('set SUPABASE_EMAIL and SUPABASE_PASSWORD to sign in')
	url = supabase_config.get_supabase_url() + '/auth/v1/token?grant_type=password'
	headers = { 'apikey': supabase_config.get_supabase_key(), 'Content-Type': 'application/json' }
	session = request('POST', url, { 'email': email, 'password': password }, headers)
	SESSION.update(access_token = session['access_token'], expires_at = time.time() + session.get('expires_in', 3600) - 60)


def get_access_token() -> str:
	if not SESSION.get('access_token') or time.time() >= SESSION.get('expires_at', 0):
		sign_in()
	return SESSION['access_token']


def rest(method : str, table : str, payload : Optional[Any] = None, params : Optional[Dict[str, str]] = None) -> Any:
	if not is_configured():
		raise SupabaseError('supabase is not configured')
	url = supabase_config.get_rest_url(table) + ('?' + urlencode(params) if params else '')
	headers = supabase_config.get_supabase_headers()
	headers['Authorization'] = 'Bearer ' + get_access_token()
	headers['Prefer'] = 'return=representation'
	return request(method, url, payload, headers)


def create_run(run : Dict[str, Any]) -> Optional[str]:
	rows = rest('POST', 'runs', run)
	return rows[0]['id'] if rows else None


def update_run(run_id : str, changes : Dict[str, Any]) -> None:
	rest('PATCH', 'runs', changes, { 'id': 'eq.' + run_id })


def list_runs(limit : int = 50, status : Optional[str] = None) -> List[Dict[str, Any]]:
	params = { 'select': '*', 'order': 'created_at.desc', 'limit': str(limit) }

	if status:
		params['status'] = 'eq.' + status
	return rest('GET', 'runs', params = params)


def save_preset(name : str, args : Dict[str, Any], description : Optional[str] = None) -> None:
	rest('POST', 'presets', { 'name': name, 'args': args, 'description': description }, { 'on_conflict': 'user_id,name' })


def list_presets() -> List[Dict[str, Any]]:
	return rest('GET', 'presets', params = { 'select': '*', 'order': 'name.asc' })


def safe(callback : Any, *args : Any, **kwargs : Any) -> Any:
	try:
		return callback(*args, **kwargs)
	except SupabaseError as exception:
		logger.warn('supabase: ' + str(exception), __name__)
		return None
