# lambda_function.py
import json
import boto3
import base64
import os

rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = os.environ['BUCKET_NAME']
    
    # Parse the event body
    body = json.loads(event['body'])
    image_base64 = body.get('image')
    filename = body.get('filename')
    
    if not image_base64 or not filename:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Missing image or filename'})
        }
    
    # Decode base64 image and upload to S3
    image_bytes = base64.b64decode(image_base64)
    image_key = f"uploads/{filename}"
    
    try:
        # Upload to S3
        s3.put_object(
            Bucket=bucket,
            Key=image_key,
            Body=image_bytes,
            ContentType='image/jpeg'
        )
        
        # Detect faces
        response = rekognition.detect_faces(
            Image={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': image_key
                }
            },
            Attributes=['ALL']
        )
        
        people_count = len(response['FaceDetails'])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Detected {people_count} people in the image',
                'people_count': people_count
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }