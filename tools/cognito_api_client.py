#!/usr/bin/env python3

import boto3
import requests
import json
import os

NEW_PASSWORD = os.environ.get('NEW_PASSWORD', 'new_password')
class CognitoAPIClient:
    def __init__(self, user_pool_id, client_id, region='us-east-1'):
        self.user_pool_id = user_pool_id
        self.client_id = client_id
        self.region = region
        self.cognito_client = boto3.client('cognito-idp', region_name=region)
        self.access_token = None
    
    def authenticate(self, username, password):
        """Authenticate user and get access token"""

        print(f"response user name {username} and pass {password}")



        try:
            response = self.cognito_client.initiate_auth(
                ClientId=self.client_id,
                AuthFlow='USER_PASSWORD_AUTH',
                AuthParameters={
                    'USERNAME': username,
                    'PASSWORD': password
                }
            )
            print(f"Auth response {response}")
            if response.get('ChallengeName') == 'NEW_PASSWORD_REQUIRED':
                session = response['Session']

                challenge_response = self.cognito_client.respond_to_auth_challenge(
                    ClientId=self.client_id,
                    ChallengeName='NEW_PASSWORD_REQUIRED',
                    Session=session,
                    ChallengeResponses={
                        'USERNAME': username,
                        'NEW_PASSWORD': NEW_PASSWORD
                    }
                )
            
                print("Password changed successfully on first sign-in.")
                response = self.cognito_client.initiate_auth(
                    ClientId=self.client_id,
                    AuthFlow='USER_PASSWORD_AUTH',
                    AuthParameters={
                        'USERNAME': username,
                        'PASSWORD': NEW_PASSWORD
                    }
                )

            # Use ID token for API Gateway (not access token)
            self.access_token = response['AuthenticationResult']['IdToken']
            print(f"Authentication successful")
            return self.access_token


        except self.cognito_client.exceptions.NotAuthorizedException:
            print("Incorrect username or password.")
            response = self.cognito_client.initiate_auth(
                    ClientId=self.client_id,
                    AuthFlow='USER_PASSWORD_AUTH',
                    AuthParameters={
                        'USERNAME': username,
                        'PASSWORD': NEW_PASSWORD
                    }
                )
            self.access_token = response['AuthenticationResult']['IdToken']
            print(f"Authentication successful")
            return self.access_token         
        except self.cognito_client.exceptions.UserNotFoundException:
            print("User not found.")
        except self.cognito_client.exceptions.InvalidPasswordException as e:
            print(f"Invalid password: {e}")
        except Exception as e:
            print(f"Authentication failed: {e}")
            return None
    
    def call_api(self, api_url, method='GET', data=None):
        """Call API Gateway with Cognito token"""
        if not self.access_token:
            print("No access token. Please authenticate first.")
            return None
        
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'Content-Type': 'application/json'
        }
        
        try:
            if method.upper() == 'POST':
                response = requests.post(api_url, headers=headers, json=data, timeout=30)
            else:
                response = requests.get(api_url, headers=headers, timeout=30)
            
            print(f"API Response Status: {response.status_code}")
            if response.status_code == 200:
                print("Success!")
                return response.json() if response.content else None
            else:
                print(f"Failed with status {response.status_code}: {response.text}")
                return response.json() if response.content else None
                
        except Exception as e:
            print(f"API call failed: {e}")
            return None

def main():
    # Configuration - replace with your values
    USER_POOL_ID = os.environ.get('USER_POOL_ID', 'userpoolid')
    CLIENT_ID = os.environ.get('CLIENT_ID', 'clientid')
    API_URL = os.environ.get('API_URL', 'apiurl')
    
    # Credentials
    USERNAME = os.environ.get('USERNAME', 'newuser')
    PASSWORD = os.environ.get('PASSWORD', 'password')
    
    # Initialize client
    client = CognitoAPIClient(USER_POOL_ID, CLIENT_ID)
    
    # Authenticate
    token = client.authenticate(USERNAME, PASSWORD)
    
    if token:
        # Call API Gateway
        print(f"\nCalling API: {API_URL}")
        
        # GET request
        # result = client.call_api(API_URL)
        # print(f"GET Response: {result}")
        
        # POST request with data
        post_data = {"requestData": "terraform code for ec2"}
        result = client.call_api(API_URL, method='POST', data=post_data)
        print(f"POST Response: {result}")

if __name__ == '__main__':
    main()
