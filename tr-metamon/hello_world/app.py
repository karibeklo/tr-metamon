# sam-app/src/my-function/handler.py
import json
import os
import mysql.connector
from mysql.connector import Error

def get_db_connection():
    """データベース接続を取得"""
    try:
        connection = mysql.connector.connect(
            host=os.environ.get('DB_HOST', 'host.docker.internal'),
            port=int(os.environ.get('DB_PORT', '3307')),
            database=os.environ.get('DB_NAME', 'metamondb'),
            user=os.environ.get('DB_USER', 'admin'),
            password=os.environ.get('DB_PASSWORD', 'MetamonMetamon'),
            autocommit=True
        )
        return connection
    except Error as e:
        print(f"Database connection error: {e}")
        raise e

def lambda_handler(event, context):
    """Lambda関数のメインハンドラー"""
    
    try:
        # データベース接続
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        query="""
        SELECT
	        episode.episodeId AS id,
            episode.name,
            episode.seriesId,
            series.seriesName,
            keyword.keyword,
            genre.formatGenre,
            genre.formatGenreName
        FROM metamondb.episode 
            LEFT JOIN series ON series.seriesId = episode.seriesId
            LEFT JOIN keyword ON keyword.episodeId = episode.episodeId
            LEFT JOIN genre ON genre.formatGenre = episode.formatGenre
        WHERE episode.episodeId= "BBBB";
        """

        # SQLクエリ実行
        cursor.execute(query)
        results = cursor.fetchall()
        
        # 接続を閉じる
        cursor.close()
        conn.close()
        
        # データ構造を安全に構築
        episode = {
            "id": results[0].get("id"),
            "name": results[0].get("name"),
            "partOfSeries": {
                "id": results[0].get("seriesId"),
                "name": results[0].get("seriesName")
            },
            "identifierGroup": {
                "formatGenreTag": [{
                    "id": results[0].get("formatGenre"),
                    "name": results[0].get("formatGenreName")
                }]
            }
        }
        
        # キーワードを収集（複数行対応）
        keywords = []
        for row in results:
            if row.get("keyword") and row["keyword"] not in keywords:
                keywords.append(row["keyword"])
        episode["keyword"] = keywords

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Success',
                'episode': episode
            }, default=str)  # datetime対応
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'Internal server error',
                'error': str(e)
            })
        }