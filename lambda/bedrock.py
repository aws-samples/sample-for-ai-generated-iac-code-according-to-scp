import json
import boto3, logging, os
from botocore.config import Config

logging.basicConfig(format='%(datefmt)s %(message)s', datefmt='%m/%d/%Y %I:%M:%S %p')

try:
    contexts3 = os.environ.get('s3bucketforcontext', None)
    if not contexts3:
        logging.error("S3 bucket name not found in environment variable 's3bucketforcontext'")
except Exception as e:
    logging.error(f"Exception at the context {e}")

bedrock_client= ''
bedrockregion = os.environ.get('bedrockregion', 'us-east-1')
logging.info(f"region for bedrock agent is {bedrockregion}")
contexts3region = os.environ.get('contexts3region', 'us-east-1')

# Configure boto3 with proper timeouts and retries for VPC environment
bedrock_config = Config(
    region_name=bedrockregion,
    retries={'max_attempts': 3, 'mode': 'adaptive'},
    connect_timeout=60,
    read_timeout=300
)

# create Bed rock client
def bedrock_client():
             
    return boto3.client('bedrock', region_name=bedrockregion)


def get_bedrock_status(bedrock_client):
    """
    Returns the status of the bedrock service.
    """
    return bedrock_client.get_status()

# Initiate specific model, cohere is used as below
def get_response_bedrock(bedrock_client,message):
    try:  
        # Get environment variables
        guardrail_id = os.environ.get('GUARDRAIL_ID')
        guardrail_version = os.environ.get('GUARDRAIL_VERSION')

        model_id = "us.amazon.nova-pro-v1:0"
        
        # Configure the inference parameters.
        inf_params = {"maxTokens": 500, "topP": 0.9, "topK": 20, "temperature": 0.7}
        system_list = [
                {
                    "text": "Act as a creative code assistant. When the user provides you with a topic, write a code for infrastructure."
                }
          ]
        message_list = [
              {"role": "user", "content": [{"text": f"{message}"}]},
          ]

        native_request = {
              "schemaVersion": "messages-v1",
              "messages": message_list,
              "system": system_list,
              "inferenceConfig": inf_params,
          } 
      

        request = json.dumps(native_request)

        # Only include guardrail parameters if they are set
        invoke_params = {
            "modelId": model_id,
            "body": request,
            "trace": "ENABLED"
        }
        
        if guardrail_id and guardrail_version:
            invoke_params["guardrailIdentifier"] = guardrail_id
            invoke_params["guardrailVersion"] = guardrail_version

        response = bedrock_client.invoke_model(**invoke_params)
        
        response_body = json.loads(response["body"].read())

                # Check for guardrail violations
        if 'guardrailAction' in response and response['guardrailAction'] == 'BLOCKED':
                logging.warning(f"Content blocked by guardrail: {response.get('guardrailReason', 'Unknown reason')}")
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'Content blocked by responsible AI guardrail',
                        'reason': response.get('guardrailReason', 'Policy violation detected')
                    })
                }
        
        completion = response_body["output"]["message"]["content"][0]["text"]
        return completion
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }      

def lambda_handler(event, context):
    
    
    
    # lambda handler 
    

    # The event should input the message similar to `Need terraform  code for the ec2`
    try:
      if "event" in event:
         userinput =  event["event"]
         logging.info(f"the event is {event['event']}") 
      elif "requestData" in event:
         userinput =  event["requestData"]
         logging.info(f"the event is {event['requestData']}") 
      else:
         raise Exception(" No valid input received")    
      
    except Exception as e:
      logging.info(f"No Valid user input {str(e)}")
      #userinput = "Terraform  code for the ec2" #|| "Terraform code for the ec2"
      
    userinputinlist = userinput.split(" ")
    appendingstr = matcher(userinputinlist)
    
    #"============== code generation with added context =================="
    logging.info(f"appended {appendingstr} with user input {userinput}") 
    changedip = userinput + ' ' + appendingstr
    

    logging.info(f"we have the messaeg asking the quesiton as {changedip} \n")
    logging.info(f"====================================================== \n")    

    bedrock_client = boto3.client('bedrock-runtime', config=bedrock_config)

    response = get_response_bedrock(bedrock_client,changedip)

    # Check if response is a dictionary (error case) or string (success case)
    if isinstance(response, dict):
        return response
    else:
        response = "code generated for " +userinput +" "+ appendingstr + " " + response
  
    logging.info(response) 

    return ( f""" {response} """ )

# Remove empty objects from dictionary
def remove_empty(d):
    if isinstance(d, dict):
        return {k: remove_empty(v) for k, v in d.items() if v not in [None, "", [], {}] and remove_empty(v) not in [None, "", [], {}]}
    elif isinstance(d, list):
        return [remove_empty(item) for item in d if item not in [None, "", [], {}] and remove_empty(item) not in [None, "", [], {}]]
    return d    

def s3crawl():
     
     allpolicy  = {'action':[],'notaction':[]}
     
     # Check if S3 bucket is configured
     if not contexts3:
         logging.error("S3 bucket name not configured in environment variable 's3bucketforcontext'")
         return allpolicy
     
     # Configure S3 client with timeout settings
     config = boto3.session.Config(
         region_name=contexts3region,
         retries={'max_attempts': 3, 'mode': 'adaptive'},
         connect_timeout=10,
         read_timeout=30
     )
     s3client = boto3.client('s3', config=config)
     
     # SCP context shall be retrieved from below folder 
     prefix = 'genai/'
     try:
         response = s3client.list_objects_v2(Bucket=contexts3, Delimiter='/', Prefix=prefix)
     except Exception as e:
         logging.error(f"S3 list_objects_v2 failed: {str(e)}")
         return allpolicy
     requiredfld = {}
     if 'Contents' not in response:
         logging.warning("No objects found in S3 bucket with specified prefix")
         return allpolicy
         
     responseContent = response['Contents']
     responseContent = remove_empty(responseContent)
     
     for object in responseContent:
        try:
            fileobject = s3client.get_object(Bucket=contexts3, Key=object['Key'])
            filecontent = fileobject['Body'].read().decode('utf-8')
            filecontent = json.loads(filecontent)
            logging.info(filecontent)
        except Exception as e:
            logging.error(f"Failed to read S3 object {object['Key']}: {str(e)}")
            continue 
        try:
     
          requiredfld = filecontent['Action']['Deny']
          allpolicy['action'].extend(requiredfld)

          logging.info(f"requiredfile content for formation of the context --- {requiredfld}") 
        except:
         logging.info("error at action => deny statement")     

        try:
     
          requiredfld = filecontent['NotAction']['Deny']
          allpolicy['notaction'].extend(requiredfld)

        except:
         logging.info("error at notaction => deny statement")     

     return allpolicy

def matcher(userinputinlist):
    logging.info(f"user input list {userinputinlist}") 
    contextformation = ""
    context=[]
    allpolicy = {'action':[],'notaction':[]}
    try:
       allpolicy = s3crawl()
    except Exception as e:
       logging.info(f"Exception in crawling {e}")
       return contextformation
    logging.info(f"====> action and no {allpolicy}") 

    try:   
      for alplist in allpolicy['action']:
         # context matching for the user request is done to append the string to prompt for scp related output
         logging.info(f"the keys are =====> {alplist}")
         alp = alplist
         logging.info(f"the keys are  {alp.keys}") 
         for requirements in alp.keys():
                logging.info(f"=====> requirements is {requirements} , with the resources as {alplist[requirements][2]}")

                contextbuilt = []
                listvalues=""
                requireditems=[]

                for listvalues in alplist[requirements][2]:
                    logging.info(f"listvalues before if {listvalues} and \n the array {alp[requirements][2]}") 
                    if listvalues in userinputinlist or listvalues=="*":
                      logging.info(f"listvalues {listvalues}") 
                      for requirecondition in (alp[requirements][1]["conditions"]).keys(): 
                        conditiontest = alp[requirements][1]["conditions"][requirecondition]
                        logging.info(f"req as the actual requirement {conditiontest}")   
                        if conditiontest[0] == "Null" and "true" in conditiontest[3]:

                           contextformation = contextformation +"\t" + f"with {conditiontest[1]} key  as {conditiontest[2]}"

                           logging.info(f"contextformation")
                        else:
                           condstest = "\t"
                           for opts in conditiontest[3]:
                               condstest = condstest + str(opts) + "\t" 
                           contextformation = contextformation +"\t" + f"with {conditiontest[1]} {conditiontest[2]}  {condstest}"
                           logging.info(f"contextformation")
    except Exception as e:
     logging.error(f"exception in string formation {e}") 
     return(contextformation)                          

    try:   
      for alplist in allpolicy['notaction']:

         logging.info(f"the keys are =====> {alplist}") 
         alp = alplist
         logging.info(f"the keys are  {alp.keys}")  
         for requirements in alp.keys():
                logging.info(f"=====> requirements is {requirements} , with the resources as {alplist[requirements][2]}") 

                contextbuilt = []
                listvalues=""
                requireditems=[]

                for listvalues in alplist[requirements][2]:
                    logging.info(f"listvalues before if {listvalues} and \n the array {alp[requirements][2]}") 
                    if listvalues not in userinputinlist or listvalues=="*":
                      logging.info(f"listvalues {listvalues}") 
                      for requirecondition in (alp[requirements][1]["conditions"]).keys(): 
                        conditiontest = alp[requirements][1]["conditions"][requirecondition]
                        logging.info(f"req as the actual requirement {conditiontest}") 
                        condstest = "\t"
                        for opts in conditiontest[2]:
                               condstest = condstest + opts + "\t"
                        # Elseif conditions could be appended in this section as per user needs to address and manage prompt for SCP conditional policies in SCP             
                        if conditiontest[0] == "StringNotEquals":

                           contextformation = contextformation +"\t" + f"with {conditiontest[1]} has to have a value within  {condstest}"

                           logging.info(f"contextformation") 
                        else:
                           #print(f"{contextformation}---- {conditiontest[1]} .... {conditiontest[0]}  for {condstest}")
                           contextformation = contextformation +"\t" + f"with {conditiontest[1]} with condition opposite to {conditiontest[0]}  for {condstest}"
                           logging.info(f"contextformation") 
                    else:
                        pass        


                        
      return(contextformation)
    except Exception as e:
     logging.error(f"exception in string formation {e}")  
     return(contextformation)