import json
import boto3
import pprint, os, json, re, logging

logging.basicConfig(format='%(datefmt)s %(message)s', datefmt='%m/%d/%Y %I:%M:%S %p')

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    i = 0
    
    if event["detail"]["eventName"]=="CreatePolicy":
        try:
            # Extract policy details from the CloudTrail event
            # policy_details = event['responseElements']['policy']['policySummary']
            policy_id = event["detail"]["responseElements"]["policy"]["policySummary"]["id"]
            policy_name = event["detail"]["responseElements"]["policy"]["policySummary"]["name"]
            
            
            
            # Store in DynamoDB
            store_policy_mapping(
                policy_id=policy_id,
                policy_name=policy_name
                
            )
            
            logger.info(f"Successfully stored mapping for policy {policy_name} ({policy_id})")
            
            
        
        
    
            
    # Dictionary to store IAM policy resources and their associated actions
            resources = {
            'Action': {'Allow': [], 'Deny': []},  
            'NotAction': {'Deny': []}
            }

            
            logging.info(f"log-group: {event['detail']}")
            content = json.loads(event['detail']['requestParameters']['content']) # Parse JSON content from AWS CloudTrail event
            
            # Iterate through each Statement in the SCP policy
            for x in content["Statement"]:
                i += 1 # Counter to keep track of statement number
                replacearnextract = []
                try:
                    # Handle both list and string formats of Action
                    if 'Action' in x:
                        if type(x["Action"]) == list:
                            actions= x['Action']
                        else:
                            actions= [x['Action']]
                        action_type = 'Action'
                    
                    elif 'NotAction' in x:
                        # Handle both list and string formats of NotAction
                        if type(x['NotAction']) == list:
                            actions= x['NotAction']
                
                        else:
                            actions= [x['NotAction']]
                        action_type = 'NotAction'
                    
                    else:
                        continue
                    
                    if type(actions)== list:
                        # Handle list of actions using list comprehension and extracts the service and permission components from it
                        resourceAction = [item for action in actions for item in action.split(":")]
                    else:
                        # Handle single action string
                        resourceAction = [action.split(":") for action in actions]
                    
                    effect = x['Effect'] #stores Effect type i.e 'Allow' or 'Deny'
                
                    sid = x.get('Sid', f'Statement{i}') #stores the statement id
                        
                    resources[action_type][effect].extend([{sid:[]}])
                    
                    
                    actelements={'actionelements':actions} # Create a dictionary to store the original action elements
                    resources[action_type][effect][-1][sid] = [actelements] # assigns the action elements to the resources dictionary under corresponding action_type and effect
                    current_req = resources[action_type][effect][-1][sid] # stores the current statement's action details
                    
                    
                    result_dict = {
                        
                        'conditions': {}         # Initialize conditions dictionary
                    }
                    result_dict_no_condition={"conditions": {"req1": [" ", "", " ", [""]]}}
                    req_counter = 1
                    # Checks if the statement has a condition
                    if 'Condition' in x:
                        for operator, conditions in x['Condition'].items():
                            for key, value in conditions.items():
                                condition_list = []
                                
                                condition_list.append(operator)   # Add operator (e.g., StringEquals)
                                
                                if '/' in key:

                                    condition_list.extend(key.split('/')) # Split the key and add the tags as well to the conditions list
                                else:

                                    condition_list.append(key)# Add condition key (e.g., aws:RequestTag)
                                    condition_list.append(" ") # Add extra space incase no tag is given in the key
                                        
                                # Handle the value
                                if isinstance(value, list):
                                    condition_list.append(value)  # Add list as a single element
                                else:
                                    condition_list.append([value])  # Convert single value to list
                            
                                # Add to conditions dictionary
                                req_key = f'req{req_counter}'
                                result_dict['conditions'][req_key] = condition_list
                                req_counter += 1
                        resources[action_type][effect][-1][sid].append(result_dict) # update the dictionary to include the conditions
                    else:
                        resources[action_type][effect][-1][sid].append(result_dict_no_condition)  
                    # Handles cases where only one Resource is the target of the statement
                    if type(x['Resource'])!=list:     
                        res=x['Resource']
                        try:
                            
                            if res!="*":
                                # split the ARN of the resource
                                arnextract = res.split(":")
                                replacearnextract.append(re.sub("(\w+)\/\*", r"\1", arnextract[5])) # adds the last component of arn and removes any trailing '/*'
                                if arnextract[2]!="" and arnextract[2] not in replacearnextract:
                                    replacearnextract.append(arnextract[2]) # adds the resource type i.e s3 for arn of a s3 bucket
                            else:
                                replacearnextract=["*"]
                        except:
                           
                            logging.error(f"exception {e}") #prints the event detail 
                        for s in range(len(resourceAction)):
                            # Removes any duplicate resource type values to make the final resources list
                            if s%2==0 and resourceAction[s] not in replacearnextract:
                                replacearnextract.append(resourceAction[s]) 
                        #updates the dictionary with the resources list   
                        resources[action_type][effect][-1][sid].append(replacearnextract)
                    else:
                        # Handles the list of Resources for the statement
                        replacearnextract1=[]
                        #Iterate for each of the resource element
                        for j in range(len(x['Resource'])):
                            res=x['Resource'][j]
                            try:
                                if res!="*":
                                    arnextract = res.split(":")
                                    replacearnextract1.append(re.sub("(\w+)\/\*", r"\1", arnextract[5]))
                                    if arnextract[2]!="" and arnextract[2] not in replacearnextract1:
                                        replacearnextract1.append(arnextract[2])
                                else:
                                    replacearnextract1=["*"]
                                
                                for k in range(len(replacearnextract1)):
                                    if replacearnextract1[k] not in replacearnextract:
                                        replacearnextract.append(replacearnextract1[k])
                            except:
                               
                                logging.error(f"exception {e}")
                            for s in range(len(resourceAction)):
                                if s%2==0 and resourceAction[s] not in replacearnextract :
                                    replacearnextract.append(resourceAction[s])        
                        #update the dictionary with the resources list                              
                        resources[action_type][effect][-1][sid].append(replacearnextract) 

                except Exception as e:
                   
                    logging.error(f"exception occurred. {e}")
                
            
            logging.info(f"resources end block ---- {resources}")
            

            bucketSuffix = event['detail']['requestParameters']['name'] # extract the name of the SCP 
            contexts3region = os.environ.get('contexts3region', '')
            s3 = boto3.resource('s3',region_name=contexts3region)
            s3object = s3.Object(os.environ.get('s3bucketforcontext',''), f"genai/{bucketSuffix}.json") # Create a JSON object in the S3 Bucket with the SCP name
            s3object.put(Body=(bytes(json.dumps(resources).encode('UTF-8')))) # store the dictionary in the JSON object
        except Exception as e:
            logger.error(f"Error processing event: {str(e)}")
            raise

    else:

        policy_id = event["detail"]["requestParameters"]["policyId"]
        policy_name = get_policy_name(policy_id)
            
        logger.info(f"Policy deleted: {policy_name} ({policy_id})")
        delete_policy_file(policy_name)    
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Policy deleted: {policy_name} ({policy_id})',
                'policy_id': policy_id,
                'policy_name': policy_name
            })}

def store_policy_mapping(policy_id, policy_name):
    """
    Store policy details in DynamoDB
    """
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table('SCPPolicyMapping')
        
        item = {
            'policy_id': policy_id,
            'policy_name': policy_name
            
          
        }
        
        table.put_item(Item=item)
        
    except Exception as e:
        logger.error(f"Error storing policy mapping: {str(e)}")
        raise

def get_policy_name(policy_id):
    """
    Retrieve policy name from DynamoDB using policy ID
    """
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table('SCPPolicyMapping')
        
        response = table.get_item(Key={'policy_id': policy_id})
        item = response.get('Item')
        
        if item:
            return item.get('policy_name', 'Unknown')
        else:
            logger.warning(f"Policy ID {policy_id} not found in table")
            return 'Unknown'
            
    except Exception as e:
        logger.error(f"Error retrieving policy name: {str(e)}")
        return 'Unknown'
def delete_policy_file(policy_name):
    """
    Delete JSON file from S3 bucket
    """
    try:
       
        
        s3 = boto3.client('s3')
        file_key =  f"genai/{policy_name}.json"
        
        s3.delete_object(Bucket=os.environ.get('s3bucketforcontext',''), Key=file_key)
        logger.info(f"Deleted S3 file: {file_key}")
        
    except Exception as e:
        logger.error(f"Error deleting S3 file: {str(e)}")

