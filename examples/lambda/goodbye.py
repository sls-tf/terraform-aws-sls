import json

def handler(event, context):
    """Simple Python Lambda handler"""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Goodbye from Python!',
            'event': event
        })
    }
