import json

def lambda_handler(event, context):
    """
    シンプルなHello World Lambda関数
    """
    
    # シンプルなレスポンス
    response_body = {
        "message": "Hello World from Metamon Lambda!",
        "status": "success"
    }
    
    # API Gateway用のレスポンス
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(response_body)
    }