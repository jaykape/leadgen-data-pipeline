"""Lambda to write lead data"""

import os
import json
import psycopg2


DB_HOST = os.environ['DB_HOST']
DB_USER = os.environ['DB_USER']
DB_PASS = os.environ['DB_PASS']
DB_NAME = os.environ['DB_NAME']


def handler(event, context):
    try:
        body = json.loads(event['body'])
        query = event.get('queryStringParameters') or {}

        lead_name = body.get('name', 'N/A')
        lead_email = body['email']
        lead_source = query.get('source', '')

    except (KeyError, json.JSONDecodeError) as e:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': f'Invalid input: {str(e)}'})
        }

    try:
        with psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=5432
        ) as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    """
                INSERT INTO form_submission (name, email, source) 
                VALUES (%s, %s, %s) 
                RETURNING id;
                """,
                    (lead_name, lead_email, lead_source)
                )
                new_row = cursor.fetchone()
                conn.commit()

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Form submitted successfully',
                'id': new_row[0]
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
