// ==UserScript==
// @name         zasrywacz 3.0
// @match        https://karachan.org/*
// @grant        GM_xmlhttpRequest
// @connect      www.hovno.sk
// @run-at       document-end
// ==/UserScript==


const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));


function hardReset() {
    localStorage.removeItem('isRunning');
    localStorage.removeItem('isSage');
    localStorage.removeItem('isTest');
}



function applyHTML() {
    const menu = document.createElement('div');

    menu.innerHTML = `
        <div class="menu-window">
            <div class="menu-section">
                <textarea id="list-of-targets" name="message" rows="6" cols="35"></textarea>
                <input type="button" id="add-button" value="dodaj link">
                <input type="button" id="save-button" value="zapisz">
                <div id="status-text"></div>
                <label><input type="checkbox" id="sage-checkbox"> saguj</label>
                <label><input type="checkbox" id="test-checkbox"> test</label>
                <input type="button" id="start-button" value="start">
            </div>
        </div>
    `;

    document.body.appendChild(menu);
    return menu;
}



function applyCSS() {
    const style = document.createElement('style');
    style.textContent = `
        .menu-section {
            border: 1px solid #888;
            padding: 5px;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .menu-window {
            position: fixed;
            left: auto;
            right: 1%;
            top: 30%;
            max-width: 40%;
            box-sizing: border-box;
            padding: 10px;
            font-size: 1rem;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
    `;
    document.head.appendChild(style);
}



function getCooldown() {
    const label = document.querySelector(
        'button.ladda-button .ladda-label'
    );

    if (!label) {
        return Promise.reject(new Error('Reply button label not found'));
    }

    return new Promise(resolve => {
        function checkCountdown() {
            const match = label.textContent.match(/Odpisz\s*\((\d+)s\)/);

            if (match) {
                observer.disconnect();

                const seconds = Number(match[1]) + 1;
                console.log(`Countdown detected: ${seconds}s`);

                setTimeout(() => resolve(seconds), seconds * 1000);
                return true;
            }

            return false;
        }

        const observer = new MutationObserver(checkCountdown);

        if (checkCountdown()) return;

        observer.observe(label, {
            childList: true,
            characterData: true,
            subtree: true
        });
    });
}




function getRandomPictureUrl() {
    const page = Math.floor(Math.random() * 920) + 1;

    return new Promise(resolve => {
        GM_xmlhttpRequest({
            method: 'GET',
            url: `https://www.hovno.sk/galeria?strana=${page}`,

            onload: function (response) {
                const doc = new DOMParser().parseFromString(
                    response.responseText,
                    'text/html'
                );
                const images = doc.querySelectorAll('a.list-group-item.shit img');
                const randomImage = images[Math.floor(Math.random() * images.length)];
                const picture = randomImage.closest('a.list-group-item.shit');
                const title = picture.querySelector('span:not(.badge)').textContent.trim();

                console.log(title);

                const fullUrl = randomImage.src.replace(
                    '/img/thumb/',
                    '/img/full/'
                );

                resolve({
                    url: fullUrl,
                    title: title
                });
            }
        });
    });
}


function downloadAndSetFile(url, title) {
    const timestamp = Date.now().toString(); // for duplicate evasion

    return new Promise((resolve, reject) => {
        GM_xmlhttpRequest({
            method: 'GET',
            url: url,
            responseType: 'blob',

            onload: function (response) {
                if (response.status < 200 || response.status >= 300) {
                    reject(new Error(`Download failed: HTTP ${response.status}`));
                    return;
                }

                const file = new File(
                    [response.response, new Blob([timestamp])], // appending the bytes
                    title + '.jpg',
                    { type: response.response.type }
                );

                const input = document.querySelector(
                    'input.upload[name="upfile"]'
                );

                if (!input) {
                    reject(new Error('File input not found'));
                    return;
                }

                const dataTransfer = new DataTransfer();
                dataTransfer.items.add(file);

                input.files = dataTransfer.files;

                input.dispatchEvent(
                    new Event('change', { bubbles: true })
                );

                // pliczek załączony?????
                if (
                    input.files.length > 0 &&
                    input.files[0].name === file.name
                ) {
                    resolve();
                } else {
                    reject(new Error('File was not attached'));
                }
            },

            onerror: function () {
                reject(new Error('File download failed'));
            }
        });
    });
}



// MutationObserver may be needed later on
function waitForDocument() {
    return new Promise(resolve => {
        if (document.readyState === 'complete') {
            resolve();
        } else {
            window.addEventListener('load', resolve, { once: true });
        }
        console.log("document loaded")
    });
}


async function zasrywacz(isSage, isTest) {
    await waitForDocument();

    const targets = JSON.parse(localStorage.getItem('targets') || '[]');
    const currentThread = Number(localStorage.getItem('currentThread') || 0);

    // are we arriving?
    const pending = localStorage.getItem('pendingTarget') === 'true';

    if (pending) {
        localStorage.setItem('pendingTarget', 'false');

        try {
            if (isSage) {
                const emailInput = document.querySelector('input[name="email"]');
                if (emailInput) emailInput.value = 'sage';
                console.log("sage inserted")
            }

            console.log("finding a picture")
            const picture = await getRandomPictureUrl();
            console.log("picture: " + picture.url);

            await downloadAndSetFile(picture.url, picture.title);
            console.log("picture appended")

            if (!isTest) {
                document.querySelector('button.ladda-button .ladda-label').closest('button').click();
                const seconds = await getCooldown();
                console.log('waited for console ' + seconds + 'seconds')
            }
            else {
                console.log("FIRE")
            }

        }
        catch (error) {
            console.error('could not prepare post:', error);
            return;
        }
    }

    // exit routine
    if (currentThread >= targets.length) {
        localStorage.setItem('isRunning', 'false');
        localStorage.setItem('currentThread', '0');
        console.log('DONE');
        init();
        return;
    }

    const target = targets[currentThread];

    // persist state
    localStorage.setItem('currentThread', currentThread + 1);
    localStorage.setItem('pendingTarget', 'true');

    console.log('Navigating to:', target);
    window.location.href = target;
    console.log('waiting for the document')
}







function init() {
    function savelinks(links) {
        const targets = links
        .split(/\s+/) // splits on spaces, tabs, and newlines
        .map(item => item.replace(/[^a-zA-Z0-9:/?&=#._~%-]/g, ''))
        .filter(item => /^https?:\/\/\S+$/.test(item));

        localStorage.setItem('targets', JSON.stringify(targets));

        console.log(targets);
        console.log(targets.length);
        stat.innerHTML = "liczba linków: " + targets.length
    }

    const menu = document.querySelector('.menu-window');
    const list = menu.querySelector('#list-of-targets');
    const stat = menu.querySelector('#status-text');
    const save = menu.querySelector('#save-button');
    const add  = menu.querySelector('#add-button');
    const sage = menu.querySelector('#sage-checkbox');
    const test = menu.querySelector('#test-checkbox');
    const startButton = menu.querySelector('#start-button');

    let isRunning = localStorage.getItem('isRunning') === 'true'
    let isSage = localStorage.getItem('isSage') === 'true'
    let isTest = localStorage.getItem('isTest') === 'true'
    let targets = JSON.parse(localStorage.getItem('targets') || '[]')


    list.value = targets.join(' ');

    stat.innerHTML = "liczba linków: " + targets.length

    test.checked = isTest
    sage.checked = isSage


    if (isRunning){
          console.log("init(): on")
          startButton.value = "stop"
          zasrywacz(isSage, isTest);
    }
    else {
          console.log("init(): off")
          startButton.value = "start"
    }


    add.addEventListener('click', () => {
        const link = list.value + ' ' + window.location.href;
        savelinks(link);
        list.value = JSON.parse(localStorage.getItem('targets') || '[]').join(' ');
    });


    save.addEventListener('click', () => {
        const textareavalue = list.value
        savelinks(textareavalue)
    });


    sage.addEventListener('click', () => {
        let isSage = sage.checked;
        localStorage.setItem('isSage', isSage);
    });

    test.addEventListener('click', () => {
        let isTest = test.checked;
        localStorage.setItem('isTest', isTest);
    });


    startButton.addEventListener('click', () => {
        isRunning = !isRunning
        localStorage.setItem('isRunning', isRunning);

        if (isRunning){
          console.log("on")
          startButton.value = "stop"
          zasrywacz(isSage, isTest);
        }
        else {
          console.log("off")
          startButton.value = "start"
        }
    });
}




(function main() {
    applyHTML();
    applyCSS();
    init();
})();
