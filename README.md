# epub-open

Experiments with AI preparing content for language learning.

The texts are taken from the internet and adapted by LLM.
The quality is not great, because I mix requests to frontier and open weights models.
I do not care much about quality, it is an experiment and a way to learn how to control LLMs.

I use custom tools to create this content:

1) [cli-tools](https://github.com/dpurge/cli-tools) to convert markdown with my own syntax extensions to epub, pdf or mdx or export vocabulary
2) [anki-flashcards](https://github.com/dpurge/anki-flashcards) to convert word lists to Anki databases
3) [agent-tools](https://github.com/dpurge/agent-tools) to give LLM skills to write my contents
4) [workflow-ai](https://github.com/dpurge/workflow-ai) to drive small stupid models that cannot follow instructions in agent-tools
5) [lang-emacs](https://github.com/dpurge/lang-emacs) to edit markdown with my syntax extensions

These tools were not created for this repo, I have some non-public learning content of higher quality that I actually use for learning.

The content is translated to Polish, because it is my native language and its easier for me to assess the quality of Polish translation (disclosure: it is useful, but not acceptable yet).
