# Accessing Large Language Models from PostgreSQL

Large language models (LLM) provide some truly unique capacities that no other software does, but they are notoriously finicky to run, requiring large amount of RAM and compute. 

That means that mere mortals are reduced to two possible paths for experimenting with LLMs:

* Use a cloud-hosted service like [OpenAI](https://platform.openai.com/docs/overview). You get the latest models and best servers, at the price of a few micro-pennies per token. 
* Use a small [locally hosted](https://ollama.com) small model. You get the joy of using your own hardware, and only paying for the electricity.

Amazingly, you can do **either** approach, and use the same access API to hit the LLM services, because the OpenAI API has become a bit of an industry standard.


## Access Extension

Knowing this, it makes sense to build a basic OpenAI API access extension in PostgreSQL to make using the API quick and easy. The extension we built for this post has three functions:

* openai.models() returns a list of models being served by the API
* openai.prompt(context text, prompt text) returns the text answer to the prompt, evaluated using the context.
* openai.vector(prompt text) returns the vector embedding of the prompt text. 

The OpenAI API just accepts JSON queries over HTTP and returns JSON responses, so we have everything we need to build a client extension, combining native PostgreSQL [JSON support](https://www.postgresql.org/docs/current/datatype-json.html) with the [http extension](https://github.com/pramsey/pgsql-http).

There are two ways to get the extension functions:

* You can install the extension if you have system access to your database. 
* Or you can just load the `openai--1.0.sql` file, since it is 100% PL/PgSQL code. Just remember to `CREATE EXTENSION http` first, because the API extension depends on the [http extension](https://github.com/pramsey/pgsql-http).


## Local or Remote

The API extension determines what API end point to hit and what models to use by reading a handful of global variables. 

Using OpenAI is easy. 

* Sign up for an API key.
* Set up the key, URI and model variables.

```sql
SET openai.api_key = 'your_api_key_here';
SET openai.api_uri = 'https://api.openai.com/v1/';
SET openai.prompt_model = 'gpt-4o-mini';
SET openai.embedding_model = 'text-embedding-3-small';
```

Using a local [Ollama](https://ollama.com) model is also pretty easy.

* Download [Ollama](https://ollama.com).
* Verify you can run `ollama` 
	* then `ollama pull llama3.1:latest`
	* and `ollama pull mxbai-embed-large`

* Set the up the session keys

```sql
SET openai.api_uri = 'http://127.0.0.1:11434/v1/';
SET openai.api_key = 'none';
SET openai.prompt_model = 'llama3.1:latest';
SET openai.embedding_model = 'mxbai-embed-large';
```
If you want to use the same setup over multiple sessions, use the `ALTER DATABASE dbname SET variable = value` command to make the values persistent.


## Sentiment Analysis

Assuming you have your system set up, you should be able to run the `openai.models()` function and get a result. Using [Ollama](https://ollama.com) your result should look a bit like this.

```sql
SELECT * FROM openai.models();
```
```
            id            | object |       created       | owned_by 
--------------------------+--------+---------------------+----------
 mxbai-embed-large:latest | model  | 2024-11-04 20:48:39 | library
 llama3.1:latest          | model  | 2024-07-25 22:45:02 | library
```

LLMs have made sentiment analysis almost too ridiculously easy. The main problem is just convincing the model to restrict its summary of the input to a single indicative value, rather than a fully-written-out summary.

For a basic example, imagine a basic feedback form. We get freeform feedback from customers and have the LLM analyze the sentiment in a trigger on INSERT or UPDATE.

```sql
CREATE TABLE feedback (
    feedback text, -- freeform comments from the customer
    sentiment text -- positive/neutral/negative from the LLM
    );
```

The trigger function is just a call into the `openai.prompt()` function with an appropriately restrictive context, to coerce the model into only returning a single word answer.

```sql
--
-- Step 1: Create the trigger function
--
CREATE OR REPLACE FUNCTION analyze_sentiment() RETURNS TRIGGER AS $$
DECLARE
    response TEXT;
BEGIN
    -- Use openai.prompt to classify the sentiment as positive, neutral, or negative
    response := openai.prompt(
        'You are an advanced sentiment analysis model. Read the given feedback text carefully and classify it as one of the following sentiments only: "positive", "neutral", or "negative". Respond with exactly one of these words and no others, using lowercase and no punctuation',
        NEW.feedback
    );

    -- Set the sentiment field based on the model's response
    NEW.sentiment := response;

    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

--
-- Step 2: Create the trigger to execute the function before each INSERT or UPDATE
--
CREATE TRIGGER set_sentiment
    BEFORE INSERT OR UPDATE ON feedback
    FOR EACH ROW
    EXECUTE FUNCTION analyze_sentiment();
```

Once the trigger function is in place, new entries to the feedback form are automatically given a sentiment analysis as they arrive.

```sql
INSERT INTO feedback (feedback) 
    VALUES 
        ('The food was not well cooked and the service was slow.'),
        ('I loved the bisque but the flan was a little too mushy.'),
        ('This was a wonderful dining experience, and I would come again, 
          even though there was a spider in the bathroom.');

SELECT * FROM feedback;
```
```
-[ RECORD 1 ]-----------------------------------------------------
feedback  | The food was not well cooked and the service was slow.
sentiment | negative

-[ RECORD 2 ]-----------------------------------------------------
feedback  | I loved the bisque but the flan was a little too mushy.
sentiment | positive

-[ RECORD 3 ]-----------------------------------------------------
feedback  | This was a wonderful dining experience, and I would 
            come again, even though there was a spider in 
            the bathroom.
sentiment | positive
```

## Conclusion

Before LLM, sentiment analysis involved multiple moving parts and pieces. Now we can just ask the black box of the LLM for an answer, using plain English to put parameters around the request.

Local model runners like [Ollama](https://ollama.com) provide a cost effective way to test, and maybe even deploy, capable mid-sized models like [Llama3-8B](https://ai.meta.com/blog/meta-llama-3/).

