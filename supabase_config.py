import os
from typing import Dict, Optional

from facefusion import config


def get_supabase_url() -> Optional[str]:
	supabase_url = os.getenv('SUPABASE_URL') or config.get_str_value('supabase', 'supabase_url')

	if supabase_url:
		return supabase_url.rstrip('/')
	return None


def get_supabase_key() -> Optional[str]:
	return os.getenv('SUPABASE_KEY') or config.get_str_value('supabase', 'supabase_key')


def get_supabase_headers() -> Dict[str, str]:
	supabase_key = get_supabase_key()
	return\
	{
		'apikey': supabase_key,
		'Authorization': 'Bearer ' + supabase_key,
		'Content-Type': 'application/json'
	}


def get_rest_url(table : str) -> str:
	return get_supabase_url() + '/rest/v1/' + table
