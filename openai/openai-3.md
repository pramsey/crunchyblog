# Accessing More Large Language Models from PostgreSQL

The [utility extension for accessing LLMs](https://github.com/pramsey/pgsql-openai) from PostgreSQL is called `openai`, but not because it is specific to "OpenAI-the-company". Rather it refers to the API that has become standard for basic interactions with LLMs

You can use the "openai API" to access

* [OpenAI models](https://platform.openai.com/docs/overview) (naturally);
* [Anthropic](https://docs.anthropic.com/en/api/openai-sdk);
* [Deep Seek](https://api-docs.deepseek.com); 
* [Ollama](https://github.com/ollama/ollama/blob/main/docs/openai.md) for self-hosted models; and,
* many many others.

That means the one database extension can interact with multiple models. For example, I just recently signed up for Claude.

```sql
SET openai.api_key = 'my_claude_key';
SET openai.api_uri = 'https://api.anthropic.com/v1/';
SET openai.prompt_model = 'claude-3-5-sonnet-20241022';
SET openai.image_model = 'claude-3-5-sonnet-20241022';
```

So I can use Claude to test out a new feature I just added to the API, bringing images into the API call!

Here's an image from Wikimedia, of the PostgreSQL mascots doing their thing.

<img src="https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Elephant_and_a_smaller_elephant_walking.jpg/640px-Elephant_and_a_smaller_elephant_walking.jpg" />

With the image API call, we can reference the image remotely by URL, or embed the URL in the call if we have the image stored locally in the database as a `bytea`.

```sql
SELECT openai.image(
  'Give me a 15 word description of this image.',
  'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Elephant_and_a_smaller_elephant_walking.jpg/640px-Elephant_and_a_smaller_elephant_walking.jpg'
  );
```
```
Safari vehicles observe wild African elephants walking 
along a dirt path through grassland savanna.
```

Good job Claude! What does GPT4 think about it?

```sql
SET openai.api_key = 'my_openai_key';
SET openai.api_uri = 'https://api.openai.com/v1/';
SET openai.prompt_model = 'gpt-4o-mini';
SET openai.image_model = 'gpt-4-turbo';

SELECT openai.image(
  'Give me a 15 word description of this image.',
  'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Elephant_and_a_smaller_elephant_walking.jpg/640px-Elephant_and_a_smaller_elephant_walking.jpg'
  );
```
```
Two elephants near a watering hole with tourists watching from safari vehicles in a grassy savannah.
```

Ollama does not support remote URLs yet, so to use it with the `openai.image()` call we have to pass in the raw image bytes directly. Here's some SQL to download the raw image, then call the function on it.

```sql
SET openai.api_uri = 'http://127.0.0.1:11434/v1/';
SET openai.api_key = 'none';
SET openai.prompt_model = 'llama3.2:latest';
SET openai.image_model = 'llava:latest';

CREATE TABLE images (
    pk serial primary key,
    img bytea
    );

INSERT INTO images (img) VALUES (
text_to_bytea(
(http_get('https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Elephant_and_a_smaller_elephant_walking.jpg/640px-Elephant_and_a_smaller_elephant_walking.jpg')).content));

SELECT openai.image(
    'Give me a 15 word description of this image.', 
    img)
  FROM images;
```

```
An elephant is standing on a patch of grass, with its trunk 
touching the ground. In front of it, a small pond is visible. 
To the right, partially obscured by the elephant, there are 
vehicles including cars and a lorry parked. Behind the elephant, 
the landscape is open, with some trees and bushes in the 
distance under a clear sky. 
```

The local `llava` model is much smaller than the cloud-based Anthropic and OpenAI models, so the performance is not as good (it ignored the prompt to make the output shorter), but the description is still passable.


## Conclusion

* You can use the `openai` extension to query any service that supports the "openai API".  
* New functionality like the `openai.image()` function lets you analyze images from inside PostgreSQL also.


## Useful Links

* [Ollama](https://ollama.com)
* [pgsql-openai](https://github.com/pramsey/pgsql-openai)
* [Claude API](https://docs.anthropic.com/en/api/openai-sdk)
* [OpenAI API](https://platform.openai.com/docs/overview)

